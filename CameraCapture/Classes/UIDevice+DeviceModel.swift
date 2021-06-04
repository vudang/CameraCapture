//
//  UIDevice+DeviceModel.swift
//  TrezorCaptureView
//
//  Created by Petr Bobák on 19/09/2019.
//
// List of Apple's mobile device codes types:
// https://gist.github.com/adamawolf/3048717

import UIKit

public struct DeviceModel {
    public var type: String
    public var major: Int
    public var minor: Int
}

extension UIDevice {
    public var model: DeviceModel? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        
        let deviceName = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        let searchRange = NSRange(deviceName.startIndex..<deviceName.endIndex, in: deviceName)
        let pattern = "([a-zA-Z]*)(\\d*),(\\d*)"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        guard let matches = regex?.matches(in: deviceName, options: [], range: searchRange), matches[0].numberOfRanges > 2 else {
            print("Unsupported regex pattern.")
            return nil
        }
        
        guard let match = matches.first,
            let typeRange = Range(match.range(at: 1), in: deviceName),
            let majorRange = Range(match.range(at: 2), in: deviceName),
            let minorRange = Range(match.range(at: 3), in: deviceName) else {
            print("Device model could not be parsed.")
            return nil
        }
        
        guard let majorVersion = Int(String(deviceName[majorRange])),
            let minorVersion = Int(String(deviceName[minorRange])) else {
                print("Device version could not be parsed.")
                return nil
        }
        
        return DeviceModel(type: String(deviceName[typeRange]), major: majorVersion, minor: minorVersion)
    }
}
