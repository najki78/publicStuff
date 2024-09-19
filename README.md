# publicStuff

## [User2DeviceMapper](https://github.com/najki78/publicStuff/blob/main/Azure%20Automation%20Runbooks/User2DeviceMapper.ps1)
A script (run in Azure Automation runbook) to keep your user and device groups in sync. It identifies members of a user group, retrieves their Windows devices from Entra ID, and adds them to the chosen device group.
If someone leaves the user group, their devices are removed from the device group to stay current.
You can run the script regularly as an Azure Automation runbook for frequent syncing, or use the core function populateDeviceGroup in your own code.

Related article on LinkedIn: [User to Device Group Synchronisation in Entra ID](https://www.linkedin.com/pulse/user-device-group-synchronisation-entra-id-%25C4%25BEubo%25C5%25A1-nikol%25C3%25ADni-4yane/)


## [DetectDuplicatePCsAndRenameViaIntune](https://github.com/najki78/publicStuff/blob/main/Azure%20Automation%20Runbooks/DetectDuplicatePCsAndRenameViaIntune.ps1)
The script (run in Azure Automation runbook) is designed to identify duplicate Windows PC names in Microsoft Intune, generate new unique names for the duplicates, and ensure that these new names are available across Intune and Entra ID.

Related article on LinkedIn: [Automatically resolving duplicate PC names in Intune](https://www.linkedin.com/pulse/automatically-resolving-duplicate-pc-names-intune-%25C4%25BEubo%25C5%25A1-nikol%25C3%25ADni-e26me)


## [Windows Update and restart at the exact time](https://github.com/najki78/publicStuff/tree/main/Windows%20Update%20and%20restart%20at%20the%20exact%20time)

Related article on LinkedIn: [Scheduling restart after Windows Update at the exact time](https://www.linkedin.com/pulse/scheduling-restart-after-windows-update-exact-time-%25C4%25BEubo%25C5%25A1-nikol%25C3%25ADni-pptbe/?trackingId=1BQ1G%2B%2F8S9C8rENcdJokQg%3D%3D)

## Shadowing (Remote desktop services shadowing)

## Go to [najki's Wiki](https://github.com/najki78/publicStuff/wiki) for more details:

* [Microsoft's free alternative to VNC, TeamViewer, DameWare etc.](https://github.com/najki78/publicStuff/wiki/Remote-desktop-shadowing-is-Microsoft's-free-alternative-to-VNC,-TeamViewer,-DameWare-etc.-(well,-sort-of-and-only-sometimes))

* [Remote desktop services shadowing troubleshooting](https://github.com/najki78/publicStuff/wiki/Remote-desktop-shadowing-troubleshooting)

## Other

* [Intune error when applying OMA URI LocalUsersAndGroups policy](https://github.com/najki78/publicStuff/wiki/Intune-error-when-applying-OMA-URI-LocalUsersAndGroups-policy)
