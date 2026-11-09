# Lets the app hand its push registration to the Firebase plugin.
import sys
p = sys.argv[1]
s = open(p).read()
if 'capacitorDidRegisterForRemoteNotifications' in s:
    sys.exit(0)
add = '''
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }
'''
i = s.rstrip().rfind('}')
s = s[:i] + add + s[i:]
open(p, 'w').write(s)
print('AppDelegate patched')
