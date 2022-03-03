
# 2022-02-17 Lubos

# terminate all screen saver processes

#foreach ($screenSaver in (Get-Process | where ProcessName -like "*.scr")) { Stop-Process -Id $screenSaver.Id }

#Get-Process | where ProcessName -like "*.scr" | Select Id | Stop-Process

Stop-Process -Name "*.scr" -Force -PassThru