import UIKit
import ObjectiveC

// Experimental compatibility bridge for an older compiler SDK running on iPadOS 27.
// These are documented PUBLIC Objective-C methods, not private UIKit selectors.
// The SDK26 build path and its actual device behavior still require compilation/testing.
// A final SDK27 build should use the typed UISceneAccessory API instead.
enum SceneAccessoryBridge {
    struct Failure: LocalizedError {
        let description: String
        var errorDescription: String? { description }
    }

    // Both documented methods return an autoreleased Objective-C object and take
    // one object argument. takeUnretainedValue + strong references retain the results.
    private typealias ObjectMethod = @convention(c)
        (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>

    static func register(on controller: UIViewController,
                         configuration: UISceneConfiguration) throws -> NSObject {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 else {
            throw Failure(description: "此注册测试只适用于 iPadOS 27或更新版本。")
        }
        guard let accessoryClass = NSClassFromString("UISceneAccessory") else {
            throw Failure(description: "系统未提供公开 UISceneAccessory 类型；未建立独立画面。")
        }
        let factorySelector = NSSelectorFromString("externalNonInteractiveSceneAccessoryWithConfiguration:")
        let registerSelector = NSSelectorFromString("registerSceneAccessory:")
        guard let factoryMethod = class_getClassMethod(accessoryClass, factorySelector),
              let registerMethod = class_getInstanceMethod(UIViewController.self, registerSelector),
              objectReturnSignature(factoryMethod), objectReturnSignature(registerMethod) else {
            throw Failure(description: "公开外屏接口缺失或签名不匹配；停止注册，台词保持隐藏。")
        }
        let factory = unsafeBitCast(method_getImplementation(factoryMethod), to: ObjectMethod.self)
        let register = unsafeBitCast(method_getImplementation(registerMethod), to: ObjectMethod.self)
        let accessory = factory(accessoryClass as AnyObject, factorySelector, configuration)
            .takeUnretainedValue()
        let result = register(controller, registerSelector, accessory).takeUnretainedValue()
        guard let registration = result as? NSObject,
              let expectedClass = NSClassFromString("UISceneAccessoryRegistration"),
              registration.isKind(of: expectedClass) else {
            throw Failure(description: "系统未返回有效外屏注册对象；独立显示尚未验证。")
        }
        return registration
    }

    private static func objectReturnSignature(_ method: Method) -> Bool {
        guard method_getNumberOfArguments(method) == 3,
              let encoding = method_getTypeEncoding(method) else { return false }
        // @ return, implicit self + selector + one object parameter. Exact names and
        // declared signatures are recorded from Apple docs in iPadOS27-api.json.
        let signature = String(cString: encoding)
        var argumentType = [CChar](repeating: 0, count: 128)
        argumentType.withUnsafeMutableBufferPointer { buffer in
            method_getArgumentType(method, 2, buffer.baseAddress!, buffer.count)
        }
        let argumentSignature = argumentType.withUnsafeBufferPointer { buffer in
            String(cString: buffer.baseAddress!)
        }
        return signature.hasPrefix("@") && argumentSignature.hasPrefix("@")
    }
}
