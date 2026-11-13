import Foundation
import Security

// Release tooling only. No application API key is read or written here.
let service="studio.luma.release.android",account="release-keystore-password"
let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
guard CommandLine.arguments.count==2 else {exit(3)}
switch CommandLine.arguments[1] {
case "read":
    var request=query;request[kSecReturnData as String]=true;request[kSecMatchLimit as String]=kSecMatchLimitOne
    var result:CFTypeRef?;let code=SecItemCopyMatching(request as CFDictionary,&result)
    if code==errSecItemNotFound {exit(2)}
    guard code==errSecSuccess,let data=result as? Data else {fputs("Release credential unavailable (\(code))\n",stderr);exit(4)}
    FileHandle.standardOutput.write(data)
case "create":
    let data=FileHandle.standardInput.readDataToEndOfFile();guard (32...256).contains(data.count) else {exit(3)}
    var request=query;request[kSecValueData as String]=data;request[kSecAttrLabel as String]="LumaStudio Android release signing"
    let code=SecItemAdd(request as CFDictionary,nil)
    guard code==errSecSuccess else {fputs("Release credential creation failed (\(code))\n",stderr);exit(4)}
default:exit(3)
}
