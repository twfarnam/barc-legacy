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
    
    var active: Bool = false
    
    var depth: Float = Float.nan


    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var depthImage: UIImageView!
    @IBOutlet weak var outputLabel: UILabel!
    @IBOutlet weak var batteryLabel: UILabel!
    @IBOutlet weak var buttonLabel: UILabel!
    
    var lastClick: Date = Date()
    
    var batteryTimer: Timer = Timer()
    
    let synth = AVSpeechSynthesizer()
    var utterance = AVSpeechUtterance(string: "")
    
    var clickSound : SystemSoundID = 0
    var humPlayer : AVAudioPlayer!
    
    var toRGBA : STDepthToRgba?
   
    
    
    
    // MARK: Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        outputLabel.text = " "
        batteryLabel.text = " "
        
        if let clickURL = Bundle.main.url(forResource: "click", withExtension: "wav") {
            AudioServicesCreateSystemSoundID(clickURL as CFURL, &clickSound)
        }

        humPlayer = try? AVAudioPlayer.init(contentsOf: Bundle.main.url(forResource: "500", withExtension: "wav")!)
        humPlayer.numberOfLoops = -1;
       
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
        start()
    }
    
    
    
    
    
    
    
    
    
    
    
    // MARK: Start/Stop
    
    
    @IBAction func startButton(_ sender: AnyObject) {
        if (active) {
            stop()
            speak("stopped")
        } else {
            if start() {
                speak("started")
            }
        }
    }
    
    
    func start() -> Bool {
        if STSensorController.shared().isConnected() && tryStartStreaming() {
            active = true
            buttonLabel.text = "Stop"
            return true
        }
        else {
            speak("sensor not connected")
            stop()
            return false
        }
    }
    
    
    func stop() {
        active = false
        STSensorController.shared().stopStreaming()
        depthImage.image = nil
        outputLabel.text = " "
        buttonLabel.text = "Start"
    }
    
    
    
    
    
    
    
    
    // MARK: Output
   
    func speak(_ words: String) {
        // only do it if the application is active, otherwise it will play when it reactivates (awkward...)
        if (UIApplication.shared.applicationState == .active) {
            utterance = AVSpeechUtterance(string: words)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
            utterance.rate = 0.5
            synth.speak(utterance)
        }
    }
    
    func setClickRate(_ depth : Float) {
        if depth.isNaN {
            humPlayer.play()
        }
        else {
            humPlayer.stop()
            
            let rate = Double(depth/150)
            
            if lastClick.timeIntervalSinceNow * -1 > rate {
                print(lastClick.timeIntervalSinceNow, rate);
                lastClick = Date()
                AudioServicesPlaySystemSound(clickSound);
            }
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
        
        let colStart = Int(Double(w) * 0.25)
        let colEnd = Int(Double(w) * 0.75)
        let rowStart = Int(Double(h) * 0.25)
        let rowEnd = Int(Double(h) * 0.75)
        
        var depthArray: [Float] = []
        for row in rowStart...rowEnd {
            for column in colStart...colEnd {
                let depth = depthData[row * w + column] / 25.4
                if (!depth.isNaN) {
                    depthArray.append(depth)
                }
            }
        }
   
        var min: Float = Float.nan
        for depth in depthArray {
            if (min.isNaN || depth < min) {
                min = depth
            }
        }
        
        return min;
    }
   
    
    func imageFromPixels(_ pixels : UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB();
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue))
        
        let provider = CGDataProvider(data: Data(bytes: UnsafePointer<UInt8>(pixels), count: width*height*4) as CFData)
        
        let image = CGImage(
            width: width,                       //width
            height: height,                      //height
            bitsPerComponent: 8,                           //bits per component
            bitsPerPixel: 8 * 4,                       //bits per pixel
            bytesPerRow: width * 4,                   //bytes per row
            space: colorSpace,                  //Quartz color space
            bitmapInfo: bitmapInfo,                  //Bitmap info (alpha channel?, order, etc)
            provider: provider!,                    //Source of data for bitmap
            decode: nil,                         //decode
            shouldInterpolate: false,                       //pixel interpolation
            intent: CGColorRenderingIntent.defaultIntent);     //rendering intent
        
        return UIImage(cgImage: image!)
    }

    
    
    
    
    
    
    
    
    // MARK: Sensor Callbacks
   
    func sensorDidOutputDepthFrame(_ depthFrame: STDepthFrame!) {
        if (!active) {
            return;
        }
        
        let depth = getDepth(depthFrame.depthInMillimeters, w: Int(depthFrame.width), h: Int(depthFrame.height))
        
        writeLabel(depth)
        setClickRate(depth)
        
        if let renderer = toRGBA {
            let pixels = renderer.convertDepthFrame(toRgba: depthFrame)
            depthImage.image = imageFromPixels(pixels!, width: Int(renderer.width), height: Int(renderer.height))
        }
    }
    
    
    func sensorDidConnect() {
        statusLabel.text = "Connected"
        speak("sensor connected")
        start()
        updateBatteryLevel()
        batteryTimer = Timer.scheduledTimer(timeInterval: TimeInterval(10), target: self, selector: #selector(updateBatteryLevel), userInfo: nil, repeats: true)
    }
    
    
    func sensorDidDisconnect() {
        statusLabel.text = "Disconnected"
        speak("sensor disconnected")
        stop()
        batteryTimer.invalidate()
        batteryLabel.text = " "
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
        speak("depth sensor has low battery")
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



class BoxView: UIView {
    
    override func draw(_ rect: CGRect) {
        
        let h = rect.height
        let w = rect.width
        let color:UIColor = UIColor.white
        
        let centerRect = CGRect(x: (w * 0.25),y: (h * 0.25),width: (w * 0.5),height: (h * 0.5))
        let path:UIBezierPath = UIBezierPath(rect: centerRect)
        path.lineWidth = 2
        
        color.set()
        path.stroke()
    }
    
}

