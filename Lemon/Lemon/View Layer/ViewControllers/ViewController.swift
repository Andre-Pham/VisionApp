//
//  ViewController.swift
//  Lemon
//
//  Created by Andre Pham on 10/6/2023.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController, CaptureDelegate, HandDetectionDelegate, TagmataDetectionDelegate, LiveSpeechToTextDelegate {
    
    private var predictionInterval = 2
    private let captureSession = CaptureSession()
    private let synthesizer = SpeechSynthesizer()
    private let recognizer = SpeechRecognizer()
    private var tagmataDetector: DetectsTagmata = TagmataQuadrantDetector()
    private let detectionCompiler = DetectionCompiler()
    private let handDetector = HandDetector()
    private var activeHandDetection = HandDetectionOutcome()
    @WrapsToZero(threshold: 600) private var currentFrameID = 0
    private var overlayFrameSyncRequired = true
    private var isRecordingAudio = false
    /// If the app is "live" - audio is being recorded, commands being listed for
    private var isLive = false
    private var loadedCommand = ""
    private var commandHistory = [String]()
    
    private var root: LemonView { return LemonView(self.view) }
    private var image = LemonImage()
    private var predictionOverlay = PredictionBoxView()
    private var jointPositionsOverlay = JointPositionsView()
    private var proximityOverlay = ProximityView()
    private var anglesOverlay = AnglesView()
    private var handClassificationOverlay = HandClassificationView()
    private let stack = LemonVStack()
    private let buttonRowStack = LemonHStack()
    private let optionsContainer = LemonView()
    private let optionsStack = LemonVStack()
    private let speakButton = LemonIconButton()
    private let recordButton = LemonIconButton()
    private let flipButton = LemonIconButton()
    private let interruptButton = LemonIconButton()
    private let intervalSlider = LemonLabelledSlider()
    private let detectorSwitch = LemonLabelledSwitch()
    private let anglesOverlaySwitch = LemonLabelledSwitch()
    private let jointsOverlaySwitch = LemonLabelledSwitch()
    private let predictionOverlaySwitch = LemonLabelledSwitch()
    private let proximityOverlaySwitch = LemonLabelledSwitch()
    private let handClassificationSwitch = LemonLabelledSwitch()
    private let speakerModeSwitch = LemonLabelledSwitch()
    private let liveSwitch = LemonLabelledSwitch()
    private let transcriptionContainer = LemonView()
    private let transcriptionText = LemonText()
    private var overlays: [LemonUIView] {
        return [
            self.predictionOverlay,
            self.jointPositionsOverlay,
            self.proximityOverlay,
            self.anglesOverlay,
            self.handClassificationOverlay,
        ]
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupSubviews()
        self.setupObjectDetection()
        self.setupHandDetection()
        self.setupSpeechRecognition()
        self.setupSpeechSynthesizer()
        self.setupAndBeginCapturingVideoFrames()
        // Stop the device automatically sleeping
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    func setupSubviews() {
        // Video view
        self.root.addSubview(self.image)
        self.image.setFrame(to: self.root.frame)
        
        // Overlays
        for overlay in self.overlays {
            self.image.addSubview(overlay)
        }
        
        // Stack
        self.root.addSubview(self.stack)
        self.stack
            .constrainAllSides()
            .addView(self.optionsContainer)
            .addSpacer()
            .addView(self.transcriptionContainer)
        
        // Options container
        self.optionsContainer
            .constrainHorizontal(padding: 24)
            .setBackgroundColor(to: UIColor.white.withAlphaComponent(0.6))
            .setCornerRadius(to: 20)
            .addSubview(self.optionsStack)
        
        // Transcription container
        self.transcriptionContainer
            .addSubview(self.transcriptionText)
            .setBackgroundColor(to: UIColor.white)
            .setCornerRadius(to: 12)
        
        // Transcription text
        self.transcriptionText
            .constrainAllSides(padding: 12)
            .setSize(to: 16)
            
        // Options stack
        self.optionsStack
            .constrainHorizontal(padding: 24)
            .constrainVertical(padding: 16)
            .setSpacing(to: 8)
            .addView(self.buttonRowStack)
            .addView(self.intervalSlider)
            .addView(self.detectorSwitch)
            .addView(self.anglesOverlaySwitch)
            .addView(self.jointsOverlaySwitch)
            .addView(self.predictionOverlaySwitch)
            .addView(self.proximityOverlaySwitch)
            .addView(self.handClassificationSwitch)
            .addView(self.speakerModeSwitch)
            .addView(self.liveSwitch)
        
        // Button row stack
        self.buttonRowStack
            .constrainHorizontal()
            .setDistribution(to: .equalSpacing)
            .addView(self.speakButton)
            .addView(self.recordButton)
            .addView(self.flipButton)
            .addView(self.interruptButton)
        
        // Speak button
        self.speakButton
            .setIcon(to: "waveform")
            .setOnTap({
                self.synthesizer.speak("Hello Lemon! Filler text is text that shares some characteristics of a real written text, but is random or otherwise generated. It may be used to display a sample of fonts, generate text for testing, or to spoof an e-mail spam filter.")
            })
        
        // Record button
        self.recordButton
            .setIcon(to: "record.circle")
            .setOnTap({
                self.transcriptionText.setText(to: "")
                self.toggleAudioRecording()
                if !self.isRecordingAudio {
                    self.liveSwitch.switchView.setState(isOn: false, animated: true)
                }
            })
        
        // Flip button
        self.flipButton
            .setIcon(to: "arrow.clockwise.circle")
            .setOnTap({
                self.flipCamera()
            })
        
        // Interrupt button
        self.interruptButton
            .setIcon(to: "xmark.circle.fill")
            .setOnTap({
                self.synthesizer.stopSpeaking()
            })
            .setAccessibilityLabel(to: "STOP")
        
        // Interval slider
        self.intervalSlider
            .constrainHorizontal()
            .setPadding(top: 8)
        self.intervalSlider.stack
            .setSpacing(to: 16)
        self.intervalSlider.labelText
            .setText(to: "Interval")
            .setPadding(right: 30)
        self.intervalSlider.slider
            .setValues(minimumValue: 1, maximumValue: 60, value: self.predictionInterval)
            .setRoundToNearest(1)
            .setOnDrag({ value in
                self.predictionInterval = Int(value)
            })
        
        // Detector switch
        self.detectorSwitch
            .constrainHorizontal()
        self.detectorSwitch.labelText
            .setText(to: "Alternate Model")
        self.detectorSwitch.switchView
            .setOnFlick({ isOn in
                if isOn {
                    self.tagmataDetector = TagmataDetector()
                } else {
                    self.tagmataDetector = TagmataQuadrantDetector()
                }
                self.setupObjectDetection()
            })
        
        // Angles overlay switch
        self.anglesOverlaySwitch
            .constrainHorizontal()
        self.anglesOverlaySwitch.labelText
            .setText(to: "Angles Overlay")
        self.anglesOverlaySwitch.switchView
            .setOnFlick({ isOn in
                self.anglesOverlay.setHidden(to: !isOn)
            })
            .setState(isOn: false, animated: false)
        
        // Joints overlay switch
        self.jointsOverlaySwitch
            .constrainHorizontal()
        self.jointsOverlaySwitch.labelText
            .setText(to: "Joints Overlay")
        self.jointsOverlaySwitch.switchView
            .setOnFlick({ isOn in
                self.jointPositionsOverlay.setHidden(to: !isOn)
            })
            .setState(isOn: false, animated: false)
        
        // Prediction overlay switch
        self.predictionOverlaySwitch
            .constrainHorizontal()
        self.predictionOverlaySwitch.labelText
            .setText(to: "Prediction Overlay")
        self.predictionOverlaySwitch.switchView
            .setOnFlick({ isOn in
                self.predictionOverlay.setHidden(to: !isOn)
            })
            .setState(isOn: false, animated: false)
        
        // Proximity overlay switch
        self.proximityOverlaySwitch
            .constrainHorizontal()
        self.proximityOverlaySwitch.labelText
            .setText(to: "Joints Proximity Overlay")
        self.proximityOverlaySwitch.switchView
            .setOnFlick({ isOn in
                self.proximityOverlay.setHidden(to: !isOn)
            })
            .setState(isOn: false, animated: false)
        
        // Hand classification switch
        self.handClassificationSwitch
            .constrainHorizontal()
        self.handClassificationSwitch.labelText
            .setText(to: "Hand Classification Overlay")
        self.handClassificationSwitch.switchView
            .setOnFlick({ isOn in
                self.handClassificationOverlay.setHidden(to: !isOn)
            })
            .setState(isOn: false, animated: false)
        
        // Speaker mode switch
        self.speakerModeSwitch
            .constrainHorizontal()
        self.speakerModeSwitch.labelText
            .setText(to: "Speaker Mode")
        self.speakerModeSwitch.switchView
            .setOnFlick({ isOn in
                if isOn {
                    AudioSessionManager.inst.setToSpeakerMode()
                } else {
                    AudioSessionManager.inst.setToVOIPMode()
                }
            })
            .setState(isOn: true, animated: false)
        
        // Live switch
        self.liveSwitch
            .constrainHorizontal()
        self.liveSwitch.labelText
            .setText(to: "App is Live")
        self.liveSwitch.switchView
            .setOnFlick({ isOn in
                self.isLive = isOn
                if isOn {
                    self.transcriptionText.setText(to: "")
                    self.commandHistory.removeAll()
                    self.startAudioRecording()
                } else {
                    self.stopAudioRecording()
                }
            })
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        self.captureSession.stopCapturing {
            super.viewWillDisappear(animated)
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        self.image.setFrame(to: CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height))
        // React to change in device orientation
        self.setupAndBeginCapturingVideoFrames()
        self.overlayFrameSyncRequired = true
    }
    
    override func viewDidLayoutSubviews() {
        self.overlayFrameSyncRequired = true
    }
    
    private func setVideoImage(to image: CGImage) {
        self.image.setImage(image)
        if self.overlayFrameSyncRequired {
            self.matchOverlayFrame()
            self.overlayFrameSyncRequired = false
        }
    }
    
    private func matchOverlayFrame() {
        let overlaySize = self.image.imageSize
        var overlayFrame = CGRect(origin: CGPoint(), size: overlaySize).scale(toAspectFillSize: self.image.frame.size)
        // Align overlay frame center to view center
        overlayFrame.origin.x += self.image.frame.center.x - overlayFrame.center.x
        overlayFrame.origin.y += self.image.frame.center.y - overlayFrame.center.y
        for overlay in self.overlays {
            overlay.setFrame(to: overlayFrame)
        }
    }
    
    private func setupAndBeginCapturingVideoFrames() {
        self.captureSession.setUpAVCapture { error in
            if let error {
                assertionFailure("Failed to setup camera: \(error)")
                return
            }
            
            self.captureSession.captureDelegate = self
            self.captureSession.startCapturing()
        }
    }
    
    private func setupObjectDetection() {
        self.tagmataDetector.objectDetectionDelegate = self
    }
    
    private func setupHandDetection() {
        self.handDetector.handDetectionDelegate = self
    }
    
    private func setupSpeechRecognition() {
        self.recognizer.liveSpeechToTextDelegate = self
    }
    
    private func setupSpeechSynthesizer() { }
    
    private func toggleAudioRecording() {
        self.isRecordingAudio.toggle()
        if self.isRecordingAudio {
            self.recordButton.setIcon(to: "record.circle.fill")
            self.recognizer.resetTranscript()
            self.recognizer.startTranscribing()
        } else {
            self.recordButton.setIcon(to: "record.circle")
            self.recognizer.stopTranscribing()
        }
    }
    
    private func startAudioRecording() {
        guard !self.isRecordingAudio else {
            return
        }
        self.isRecordingAudio = true
        self.recordButton.setIcon(to: "record.circle.fill")
        self.recognizer.startTranscribing()
    }
    
    private func stopAudioRecording() {
        guard self.isRecordingAudio else {
            return
        }
        self.isRecordingAudio = false
        self.recordButton.setIcon(to: "record.circle")
        self.recognizer.stopTranscribing()
    }
    
    private func flipCamera() {
        self.captureSession.flipCamera { error in
            if let error {
                assertionFailure("Failed to flip camera: \(error)")
                return
            }
        }
    }
    
    func onCapture(session: CaptureSession, frame: CGImage?) {
        if let frame {
            if (!self.isLive || (self.isLive && !self.loadedCommand.isEmpty)) {
                self.handDetector.makePrediction(on: frame)
                if self.currentFrameID%self.predictionInterval == 0 {
                    self.tagmataDetector.makePrediction(on: frame)
                }
            }
            
            self.setVideoImage(to: frame)
            
            self.currentFrameID += 1
        }
    }
    
    func onTagmataDetection(outcome: TagmataDetectionOutcome?) {
        if let outcome {
            self.predictionOverlay.drawBoxes(for: outcome)
            self.proximityOverlay.drawProximityJoints(tagmataDetectionOutcome: outcome, handDetectionOutcome: self.activeHandDetection)
            self.anglesOverlay.drawOverlay(for: outcome)
            self.detectionCompiler.addOutcome(outcome, handOutcome: self.activeHandDetection)
        }
        if self.detectionCompiler.newResultsReady {
            let results = self.detectionCompiler.retrieveResults()
            self.handleDetectionResults(results)
        }
    }
    
    func onHandDetection(outcome: HandDetectionOutcome?) {
        if let outcome {
            self.jointPositionsOverlay.drawJointPositions(for: outcome)
            self.handClassificationOverlay.drawHandClassification(for: outcome)
        }
        self.activeHandDetection = outcome ?? HandDetectionOutcome()
    }
    
    func onWordRecognition(currentTranscription: SpeechText) {
        if !currentTranscription.text.isEmpty {
            self.transcriptionText.setText(to: currentTranscription.text)
        }
        if self.isLive {
            if currentTranscription.count("name") > self.commandHistory.filter({ $0 == "name" }).count {
                self.commandHistory.append("name")
                self.detectionCompiler.clearOutcomes()
                self.loadedCommand = "name"
            } else if currentTranscription.count("information") > self.commandHistory.filter({ $0 == "information" }).count {
                self.commandHistory.append("information")
                self.detectionCompiler.clearOutcomes()
                self.loadedCommand = "information"
            } else if currentTranscription.count("test") > self.commandHistory.filter({ $0 == "test" }).count {
                self.commandHistory.append("test")
                self.detectionCompiler.clearOutcomes()
                self.synthesizer.speak("Lemon")
            }
            //else if currentTranscription.contains("stop") {
            //    self.synthesizer.stopSpeaking()
            //    self.recognizer.clearLiveTranscription()
            //}
        }
    }
    
    func handleDetectionResults(_ results: CompiledResults) {
        if self.isLive {
            if let tagmata = results.heldTagmata.first {
                if self.loadedCommand == "name" {
                    self.loadedCommand = ""
                    self.synthesizer.speak(tagmata.name)
                } else if self.loadedCommand == "information" {
                    self.loadedCommand = ""
                    self.synthesizer.speak(tagmata.description)
                }
            }
        }
    }

}

