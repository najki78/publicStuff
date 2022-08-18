Remote desktop shadowing (also called shadow session mode) is built-in Windows feature (basically RDP access to the computer “console”). 
Allows IT personnel to view and interact with the remote desktop while letting the screen visible to the onsite personnel (unlike mstsc /console, it does not lock the console view for locally logged on user).

Pros:
* free (built in Windows Client OS)
* built on Remote Desktop Services (even using same mstsc.exe client to connect)
* It can be configured not to require an approval of the console user to connect (therefore suitable for the machines with no permanent presence of the user)

And now some bad news. Shadowing is useful only in a few limited scenarios.

Cons:
* Shadowing offers no indication that console is being shadowed (remotely watched) and therefore might only be used on non-sensitive machines where this does not cause a security concern (e.g. Windows 10 kiosk machines on the plant shopfloor etc)
* Requires that *someone* is logged on to the console (when the console is logged off, you can still use Remote Desktop, if enabled)
* The console session cannot be locked (you have to ensure lock screen is disabled)
* Access is allowed only to members of local Administrators on the remote machine
* No additional functionality comparing to 3rd party products (no chat with console user, file transfer etc)
* The feature is unreliable at times (local firewall issue or providing distorted image when Shadowing)


More information:
(https://social.technet.microsoft.com/wiki/contents/articles/19804.remote-desktop-services-session-shadowing.aspx)
()
