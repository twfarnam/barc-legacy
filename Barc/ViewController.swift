//
//  ViewController.swift
//  Barc
//
//  Created by Tim Farnam on 7/1/16.
//  Copyright © 2016 Tim Farnam. All rights reserved.
//

import UIKit
import AudioToolbox
import AVFoundation


class ViewController: UIViewController, STSensorControllerDelegate {
    
    // MARK: Properties
    
    var depth: Float = Float.nan

    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var depthImage: UIImageView!
    @IBOutlet weak var outputLabel: UILabel!
    @IBOutlet weak var batteryLabel: UILabel!
    
    var lastClick: Date = Date()
    
    var batteryTimer: Timer = Timer()
    
    let synth = AVSpeechSynthesizer()
    var utterance = AVSpeechUtterance(string: "")
    
    var toRGBA : STDepthToRgba?
    
    
    
    
    // MARK: Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        outputLabel.text = " "
        batteryLabel.text = " "
        
        // puts yelow border on the yellow image
        let color = UIColor.yellow;
        depthImage.layer.borderColor = color.withAlphaComponent(0.3).cgColor;
        depthImage.layer.borderWidth = 2
        
        STSensorController.shared().delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.appDidBecomeActive), name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.appWillEnterBackground), name:NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func appWillEnterBackground(_ notification: Notification) {
        stop()
    }
    
    func appDidBecomeActive() {
        do{
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
            do{
                try AVAudioSession.sharedInstance().setActive(true)
                start()
            } catch {
                
            }
        } catch {
            
        }
    }
    
    
    
    
    // MARK: Start/Stop
    
    func start() {
        if tryInitializeSensor() && tryStartStreaming() {
            outputLabel.text =  ""
            //statusLabel.text = "Connected"
        } else {
            outputLabel.text =  ""
            //statusLabel.text = "Disconnected"
        }
    }
    
    
    func stop() {
        STSensorController.shared().stopStreaming()
        depthImage.image = nil
        outputLabel.text = " "
    }
    
    
    
    // MARK: Output
   
    func speak(_ words: String) {
        // only do it if the application is active, otherwise it will play when it reactivates (awkward...)
        //if (UIApplication.shared.applicationState == .active) {
            utterance = AVSpeechUtterance(string: words)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceMaximumSpeechRate / 1.7
            utterance.volume = 1.0
            synth.speak(utterance)
        //}
    }
    
    
    func speakDepth(_ depth : Float) {
        if !synth.isSpeaking {
            var formatted: String = ""
            if depth.isNaN {
                formatted = "No reading"
            }
            else if depth < 24 {
                formatted = String(format: "%.0f", depth)
            }
            else {
                formatted = String(format: "%.0f", depth / 12) + " feet"
            }
            speak(formatted)
        }
    }
    
    
    func writeLabel(_ depth : Float) {
        if depth.isNaN {
             outputLabel.text = "Don't Know"
        }
        else {
            outputLabel.text = String(format: "%.1f", depth) + "\""
        }
    }
    
    
    
    
    // MARK: Data
    
    func getDepth(_ depthData : UnsafeMutablePointer<Float>, w: Int, h: Int) -> Float {

        var min: Float = Float.nan
        for i in 0...(w*h-1) {
            let depth = depthData[i]
            if (min.isNaN || depth < min) {
                min = depth
            }
        }
        
        return min / 25.4;
    }
    
    
    func imageFromPixels(_ pixels : UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB();
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue))
        
        let provider = CGDataProvider(data: Data(bytes: UnsafePointer<UInt8>(pixels), count: width*height*4) as CFData)
        
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * 4,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider!,
            decode: nil,
            shouldInterpolate: false,
            intent: CGColorRenderingIntent.defaultIntent
        );
        
        return UIImage(cgImage: image!)
    }

    
    
    
    
    
    
    
    
    // MARK: Sensor Callbacks
   
    func sensorDidOutputDepthFrame(_ depthFrame: STDepthFrame!) {
        
        let depth = getDepth(depthFrame.depthInMillimeters, w: Int(depthFrame.width), h: Int(depthFrame.height))
        
        speakDepth(depth)
        //writeLabel(depth)
        
        //if let renderer = toRGBA {
        //   let pixels = renderer.convertDepthFrame(toRgba: depthFrame)
        //   depthImage.image = imageFromPixels(pixels!, width: Int(renderer.width), height: Int(renderer.height))
        //}
    }
    
    
    func sensorDidConnect() {
        //statusLabel.text = "Connected"
        speak("connected")
        start()
        updateBatteryLevel()
        batteryTimer = Timer.scheduledTimer(timeInterval: TimeInterval(10), target: self, selector: #selector(updateBatteryLevel), userInfo: nil, repeats: true)
    }
    
    
    func sensorDidDisconnect() {
        //statusLabel.text = "Disconnected"
        speak("disconnected")
        stop()
        batteryTimer.invalidate()
        batteryLabel.text = ""
    }
    
    
    func updateBatteryLevel() {
        let batteryLevel = STSensorController.shared().getBatteryChargePercentage()
        batteryLabel.text = "\(batteryLevel)% battery"
        if batteryLevel < 10 {
            batteryLabel.textColor = UIColor.red
        } else {
            batteryLabel.textColor = UIColor.black
        }
    }
    
    
    func sensorDidStopStreaming(_ reason: STSensorControllerDidStopStreamingReason) {}
    func sensorDidLeaveLowPowerMode() {}
    
    func sensorBatteryNeedsCharging() {
        speak("depth scanner has low battery")
    }

    
    
    
    
    
    // MARK: Sensor Control
    
    
    func tryInitializeSensor() -> Bool {
        let result = STSensorController.shared().initializeSensorConnection()
        print(result)
        if result == .alreadyInitialized || result == .success {
            return true
        }
        return false
    }
    
    
    @discardableResult
    func tryStartStreaming() -> Bool {
        if tryInitializeSensor() {
            let options : [AnyHashable: Any] = [
                kSTStreamConfigKey: NSNumber(value: STStreamConfig.depth320x240.rawValue as Int),
                kSTFrameSyncConfigKey: NSNumber(value: STFrameSyncConfig.off.rawValue as Int),
                kSTHoleFilterEnabledKey: true
            ]
            do {
                try STSensorController.shared().startStreaming(options: options as [AnyHashable: Any])
                let toRGBAOptions : [AnyHashable: Any] = [
                   kSTDepthToRgbaStrategyKey : NSNumber(value: STDepthToRgbaStrategy.redToBlueGradient.rawValue as Int)
                ]
                toRGBA = STDepthToRgba(options: toRGBAOptions)
                return true
            } catch let error as NSError {
                print(error)
            }
        }
        return false
    }
    
    
    
}
