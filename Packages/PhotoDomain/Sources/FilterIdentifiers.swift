import Foundation

public enum FilterIdentifiers {
    public static let builtIn=["natural","portrait","film","warm","cool","clean","ivory","rose","peach","softPortrait","amber","golden","copper","sunset","silver","mono","matteMono","noir","forest","jade","ocean","alpine","faded","vintage","instant","cinema","tealOrange","night","pastel","airy"]
    public static func isValid(_ id: String)->Bool {
        builtIn.contains(id) || id.range(of:"^user_[a-f0-9]{64}$",options:.regularExpression) != nil
    }
}
