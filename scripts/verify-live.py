"""Check deployed HTTPS routes using the owner's local admin credential, without printing secrets."""
import json
import urllib.request
from pathlib import Path

credentials = json.loads((Path.home() / '.local/share/my-chuannong/production/credentials.json').read_text())
api = 'https://chuannong-api.mychangliapp.cn'
admin = 'https://chuannong-admin.mychangliapp.cn'
files = 'https://chuannong-files.mychangliapp.cn'
results = []

def call(base, path, method='GET', body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if base == admin:
        headers['Origin'] = admin
    request = urllib.request.Request(base + path, json.dumps(body).encode() if body is not None else None, headers, method=method)
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read())
        assert response.status == 200 and payload['ok'], path
        results.append({'url': base + path, 'method': method, 'httpStatus': response.status, 'ok': True})
        return payload.get('data', payload)

for base in (api, admin, files):
    call(base, '/health')
call(api, '/ready')
login = call(admin, '/api/v1/auth/login', 'POST', {'username': credentials['adminUsername'], 'password': credentials['adminPassword']})
token = login['token']
try:
    assert call(api, '/api/v1/auth/me', token=token)['role'] == 'ADMIN'
    call(admin, '/api/v1/admin/overview', token=token)
    assert call(admin, '/api/v1/admin/resources', token=token) == []
    assert call(admin, '/api/v1/admin/announcements', token=token) == []
    admins = call(admin, '/api/v1/admin/admins', token=token)
    assert len(admins) == 1 and admins[0]['username'] == credentials['adminUsername']
finally:
    call(admin, '/api/v1/auth/logout', 'POST', {}, token=token)
output = Path(__file__).resolve().parents[1] / 'outputs/live-verification.json'
output.write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
print(f'{len(results)} deployed HTTPS/API checks passed; administrator login/logout verified; resource and announcement lists are empty.')
