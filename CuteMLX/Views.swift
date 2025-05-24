//
//  Views.swift
//  CuteMLX
//
//  Created by John Mai on 2025/5/24.
//

import AsyncAlgorithms
import Metal
import MLX
import MLXLLM
import MLXLMCommon
import MLXRandom
import SwiftUI
import Tokenizers
import Lottie

@Observable
@MainActor
class LLMEvaluator {
    var running = false

    var enableThinking = false

    var prompt = ""
    var output = ""
    var modelInfo = ""
    var stat = ""

    /// This controls which model loads. `qwen2_5_1_5b` is one of the smaller ones, so this will fit on
    /// more devices.
    let modelConfiguration = LLMRegistry.qwen3_1_7b_4bit

    /// parameters controlling the output
    let generateParameters = GenerateParameters(maxTokens: 240, temperature: 0.6)
    let updateInterval = Duration.seconds(0.25)

    /// A task responsible for handling the generation process.
    var generationTask: Task<Void, Error>?

    enum LoadState {
        case idle
        case loaded(ModelContainer)
    }

    var loadState = LoadState.idle

    /// load and return the model -- can be called multiple times, subsequent calls will
    /// just return the loaded model
    func load() async throws -> ModelContainer {
        switch loadState {
        case .idle:
            // limit the buffer cache
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            let modelContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: modelConfiguration
            ) {
                [modelConfiguration] progress in
                Task { @MainActor in
                    self.modelInfo =
                        "Downloading \(modelConfiguration.name): \(Int(progress.fractionCompleted * 100))%"
                }
            }
            let numParams = await modelContainer.perform { context in
                context.model.numParameters()
            }

            prompt = modelConfiguration.defaultPrompt
            modelInfo =
                "Loaded \(modelConfiguration.id).  Weights: \(numParams / (1024 * 1024))M"
            loadState = .loaded(modelContainer)
            return modelContainer

        case .loaded(let modelContainer):
            return modelContainer
        }
    }

    private func generate(prompt: String) async {
        output = ""
        let chat: [Chat.Message] = [
            .system("You are a helpful assistant"),
            .user(prompt),
        ]
        let userInput = UserInput(
            chat: chat, additionalContext: ["enable_thinking": enableThinking]
        )

        do {
            let modelContainer = try await load()

            // each time you generate you will get something new
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

            try await modelContainer.perform { (context: ModelContext) in
                let lmInput = try await context.processor.prepare(input: userInput)
                let stream = try MLXLMCommon.generate(
                    input: lmInput, parameters: generateParameters, context: context
                )

                // generate and output in batches
                for await batch in stream._throttle(
                    for: updateInterval, reducing: Generation.collect
                ) {
                    let output = batch.compactMap(\.chunk).joined(separator: "")
                    if !output.isEmpty {
                        Task { @MainActor [output] in
                            self.output += output
                        }
                    }

                    if let completion = batch.compactMap(\.info).first {
                        Task { @MainActor in
                            self.stat = "\(completion.tokensPerSecond) tokens/s"
                        }
                    }
                }
            }

        } catch {
            output = "Failed: \(error)"
        }
    }

    func generate() {
        guard !running else { return }
        let currentPrompt = prompt
        prompt = ""
        generationTask = Task {
            running = true
            await generate(prompt: currentPrompt)
            running = false
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        running = false
    }
}

// Main content view - displays generated text
public struct MainContentView: View {
    @Bindable var llm: LLMEvaluator

    public var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(20)

            VStack(alignment: .leading, spacing: 12) {
                // Top information bar
                VStack(spacing: 8) {
                    HStack {
                        Text(llm.modelInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(llm.stat)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        if llm.running {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }

                // Output display area
                ScrollView(.vertical) {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading) {
                            Text(llm.output)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .onChange(of: llm.output) { _, _ in
                            proxy.scrollTo("bottom")
                        }

                        Spacer()
                            .frame(width: 1, height: 1)
                            .id("bottom")
                    }
                }
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
        .frame(width: 250, height: 250)
        .task {
            // Preload model
            _ = try? await llm.load()
        }
    }
}

// Input view
public struct InputView: View {
    @Bindable var llm: LLMEvaluator
    @FocusState private var isInputFocused: Bool

    public var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(20)

            HStack(spacing: 12) {
                TextField("Enter prompt...", text: $llm.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .focused($isInputFocused)
                    .disabled(llm.running)
                    .onSubmit {
                        if !llm.running {
                            llm.generate()
                        }
                    }
                    .onTapGesture {
                        isInputFocused = true
                    }

                Button(action: {
                    if llm.running {
                        llm.cancelGeneration()
                    } else {
                        llm.generate()
                    }
                }) {
                    Image(systemName: llm.running ? "stop.fill" : "paperplane.fill")
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(llm.running ? Color.red : (llm.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue))
                        .cornerRadius(18)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .frame(width: 250, height: 45)
        .onAppear {
            // Delay a bit to ensure view is fully loaded before setting focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }
}

// Control button view - Lottie animation
public struct ControlButtonView: View {
    @Bindable var llm: LLMEvaluator

    public var body: some View {
        ZStack {
            // VegetableDog animation (default state)
            LottieView(animation: .named("VegetableDog"))
                .playing(loopMode: .loop)
                .frame(width: 60, height: 60)
                .opacity(llm.running ? 0 : 1)
                .scaleEffect(llm.running ? 0.8 : 1.0)
            
            // Thinking animation (generating state)
            LottieView(animation: .named("Thinking"))
                .playing(loopMode: .loop)
                .frame(width: 60, height: 60)
                .opacity(llm.running ? 1 : 0)
                .scaleEffect(llm.running ? 1.0 : 0.8)
        }
        .frame(width: 80, height: 80)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.4), value: llm.running)
    }
}

// SwiftUI wrapper for NSVisualEffectView
public struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
