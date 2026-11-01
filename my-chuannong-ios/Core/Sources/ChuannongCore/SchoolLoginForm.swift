import Foundation

public enum SchoolLoginForm {
    // Submit the same six fields as Android. A radio/select named lb can otherwise
    // omit the student category, even after assigning its value property.
    public static let submission = #"""
    const unique = name => {
      const fields = document.querySelectorAll('input[name="' + name + '"]');
      return fields.length === 1 ? fields[0] : null;
    };
    const hour = unique('hour_key'), sign = unique('sign');
    const user = unique('user'), password = unique('pwd');
    if (!hour || !sign || !user || !password || !hour.value.trim() || !sign.value.trim()) return false;
    const original = hour.form;
    if (!original || sign.form !== original || user.form !== original || password.form !== original) return false;
    const action = new URL(original.getAttribute('action') || '/jiaoshi/bangong/check.asp', location.href);
    if (!['https:', 'http:'].includes(action.protocol) || !action.pathname.endsWith('/jiaoshi/bangong/check.asp') ||
        !(action.origin === location.origin || action.hostname === 'jiaowu.sicau.edu.cn')) return false;
    const target = new URL(destination);
    if (target.origin !== location.origin || !target.pathname.endsWith('/jiaoshi/bangong/check.asp')) return false;
    const form = document.createElement('form');
    form.method = 'POST'; form.action = target.href;
    form.acceptCharset = original.acceptCharset || document.characterSet;
    for (const [name, value] of Object.entries({user: account, pwd: secret, lb: 'S', submit: '', sign: sign.value.trim(), hour_key: hour.value.trim()})) {
      const field = document.createElement('input');
      field.type = 'hidden'; field.name = name; field.value = value; form.appendChild(field);
    }
    document.body.appendChild(form);
    HTMLFormElement.prototype.submit.call(form);
    return true;
    """#
}
