# PiSpider Windows Worker Dashboard

The Worker now runs without a command window when started from `Start-Worker.cmd` or `Activate_Worker.bat`.

The WinForms dashboard is the operator surface for the Windows side. It shows:

- Worker ONLINE/OFFLINE and AUTO state
- current activity and progress phase
- command received from SoloHost
- last result and error summary
- quick access to Worker folder, Live data and Config.json
- SoloHost connectivity test

The dashboard runs elevated through UAC. The actual `LiveWorker.ps1` process is launched hidden.

The existing Spider rules, schedules, Doctors, Actions, Safety and Recovery engines remain unchanged.
