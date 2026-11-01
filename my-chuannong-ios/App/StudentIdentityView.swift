import SwiftUI

struct StudentIdentityView: View {
    @Environment(PlatformSession.self) private var platform
    @State private var name = ""
    @State private var studentID = ""
    @State private var confirm = false
    @State private var error: String?
    private var bound: Bool { platform.user?.studentId?.isEmpty == false }
    private var valid: Bool {
        (2...40).contains(name.trimmingCharacters(in:.whitespacesAndNewlines).count)
        && studentID.range(of:"^[A-Z0-9]{6,20}$",options:.regularExpression) != nil
    }
    var body: some View {
        Form {
            if bound {
                LabeledContent("姓名",value:platform.user?.realName ?? "")
                LabeledContent("学号",value:platform.user?.studentId ?? "")
                LabeledContent("状态",value:platform.user?.identityStatus == "VERIFIED" ? "已核验" : "待核验")
            } else {
                TextField("姓名",text:$name).textContentType(.name).accessibilityIdentifier("identity-name")
                    .onChange(of:name){_,value in name=String(value.filter{!$0.isNewline}.prefix(40))}
                TextField("四川农业大学学号",text:$studentID).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .accessibilityIdentifier("identity-student")
                    .onChange(of:studentID){_,value in studentID=String(value.uppercased().filter{$0.isASCII && ($0.isLetter || $0.isNumber)}.prefix(20))}
                if platform.user?.phoneVerified != true {
                    NavigationLink("先验证绑定手机号") { PlatformLoginView(initialMode:.verify) }
                }
                Button("提交学生资料") { confirm=true }
                    .disabled(!valid || platform.user?.phoneVerified != true || platform.busy)
            }
            if let error { Text(error).foregroundStyle(.red) }
            NavigationLink("资料使用与更正规则") { LegalView(kind:.privacy) }
        }.navigationTitle("学生资料").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively).disabled(platform.busy)
            .confirmationDialog("确认姓名和学号",isPresented:$confirm,titleVisibility:.visible) {
                Button("确认并提交") {
                    Task { do { try await platform.bindStudentIdentity(studentId:studentID,realName:name);error=nil }
                        catch { self.error=error.localizedDescription } }
                }
                Button("返回检查",role:.cancel) {}
            } message: {
                Text("一个学号只能绑定一个手机号账号。提交后进入核验，无法自行换绑；资料填写错误请通过意见反馈联系管理员。")
            }
    }
}
