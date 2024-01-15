# Windows Update and restart at the exact time

If you work with Windows PCs, you know how important it is to keep them updated and secure. But sometimes, you need more control over when the updates are installed and when the PC is restarted. 

Windows Update lets you choose a time window for installing updates and restarting the PC, but it doesn't guarantee that the actual restart will happen exactly when you want it. 

For instance, Feature Update installation would take significantly longer than the regular update and when the installation and restart are scheduled to run at 6PM, one month it might restart at 6:25 and the other at 6:05. Not really predictable.

But what if you want to make sure that the updates are installed earlier and the PC is restart at certain exact time (for example, when the shifts change)? 

## How can we restart at the exact time?

Unfortunately, we cannot rely on the default Windows Update scheduler for such scenario (I checked with Microsoft Support).

That's why I decided to create a PowerShell solution that allows me to schedule the updates and the restarts with more precision and reliability.

My solution uses PSWindowsUpdate by [Michał Gajda](https://github.com/mgajda83/PSWindowsUpdate) (thank you very much!) to check for and apply any available updates a few hours before the desired restart time. I wanted to minimize the time between the updates installation and the planned restart and therefore decided for running the download and the installation 6 hours prior to the restart, this is easily customizable.

The solution consists of two scheduled tasks: one that runs the update script (**WindowsUpdateNoRestart**) and one that restarts the PC at the exact time needed (**RestartAfterWindowsUpdate**).

## The solution


[01 WindowsUpdateAndRestart6HoursLater - embedded script.ps1](https://github.com/najki78/publicStuff/blob/main/Windows%20Update%20and%20restart%20at%20the%20exact%20time/01%20WindowsUpdateAndRestart6HoursLater%20-%20embedded%20script.ps1)

The script is the one that runs as the task **WindowsUpdateNoRestart**. It is included in $scriptfile variable of the next script.


[02 WindowsUpdateAndRestart6HoursLater - template.ps1](https://github.com/najki78/publicStuff/blob/main/Windows%20Update%20and%20restart%20at%20the%20exact%20time/02%20WindowsUpdateAndRestart6HoursLater%20-%20template.ps1)

This script is the one that creates both scheduled tasks. You can customize the time interval between the update and the restart, as well as the grace period for the user to save their work before the restart (script defaults to 90 seconds).

The PC will always restart at the specified time, regardless of whether it needs to or not. I think this is a good practice to keep the system fresh and avoid potential issues. IT elders might say that the restarted system is like a mind after a good night sleep, so why not to do it?

I use SCHTASKS command line tool for the tasks scheduling because New-ScheduledTaskTrigger cmdlet does not allow to create more flexible schedules, such as 'run on every 3rd Wednesday of every second month'.

One challenge I faced was loading the [PSWindowsUpdate](https://www.powershellgallery.com/packages/PSWindowsUpdate/) module (unrelated to the module itself, that one is excellent!), because I had some issues with accessing Powershell Gallery through Zscaler. To detect the Gallery is reachable, I added some checks in the code.

The script and the "WindowsUpdateNoRestart" task write their logs to this file: _C:\ProgramData\YourFolderName\Intune\[timestamp] WindowsUpdateAndRestart.txt_


[03 WindowsUpdateAndRestart6HoursLater - generate scripts.ps1](https://github.com/najki78/publicStuff/blob/main/Windows%20Update%20and%20restart%20at%20the%20exact%20time/03%20WindowsUpdateAndRestart6HoursLater%20-%20generate%20scripts.ps1)

This code creates scripts for different schedules and uploads them to Intune using Intune Scripts.

To add a new timeslot, you need to create a new $hashTable["DayX...."] record with this structure:

- Line 1: [string] The name of the Intune Script (it will be replaced by the new version)

- Line 2: [string] Not used anymore, leave it as an empty string (used by previous version of the script for Register-ScheduledTask parameters)

- Line 3: [string] Not used anymore, leave it as an empty string

- Line 4: [string] The schedule of the **WindowsUpdateNoRestart** task using SCHTASKS (set it to run e.g. 6 hours before the restart to give enough time for the updates to download and install)

- Line 5: [string] The schedule of the **RestartAfterWindowsUpdate** task using SCHTASKS

- Line 6: [int] The restart delay in seconds (I use 90 seconds by default; to give enough time for the user to save their work). The shutdown command during those 90 seconds can be cancelled by the user (no admin rights required) during the waiting period. Just type shutdown /a in the command prompt.


For example, for line 4 and 5, you can use something like this: 

"/sc monthly /m * /mo FOURTH /d SUN /st 18:00" (fourth Sunday of the month at 6PM)

"/sc WEEKLY /d FRI /st 17:32" (every Friday at 17:32)


One limitation of the current version is that you have to create the Intune Script objects before running script "03 WindowsUpdateAndRestart6HoursLater - generate scripts.ps1", even with some dummy script. I might improve this in the future versions by creating the Intune Script automatically.

If you want to avoid unexpected restarts, you need to check if the local time and time zone settings are correct. The schedules for updates and restarts use the local time on your PC.


### To verify that the updates and restarts are working properly, follow these steps:

- Open Task Scheduler as Administrator (taskschd.msc).
- Go to your Task Scheduler folder and check the trigger of the **RestartAfterWindowsUpdate** task. It should match your desired restart time.
- Check the other task, **WindowsUpdateNoRestart**. It should be set for 6 hours before the restart time.


### To remove the Windows Update configuration from the PC, do this:

- Open Task Scheduler as Administrator (taskschd.msc).
- Delete both tasks, **RestartAfterWindowsUpdate** and **WindowsUpdateNoRestart**, in your Task Scheduler folder.
- Delete all files with _WindowsUpdateAndRestart_ in the name from **C:\ProgramData\YourFolderName\Intune\** folder (WindowsUpdateAndRestart.txt, *-WindowsUpdateAndRestart.txt and WindowsUpdateAndRestart.ps1).

I hope this helps. I also have a cleanup script and an Intune Remediation tool that can help you with this process. If you would find them useful, let me know.
