# EntertainTV_Control

<hr>
If you are looking for an openHAB integration of the Entertain/MagentaTV Media Receiver you should check the native TelekomTV binding: https://github.com/markus7017/org.openhab.binding.telekomtv
<hr>
<p>
  
Small script to control the Telekom Entertain Receiver with openHAB

Usage: sudo ./entertain_control.sh on | off | status | presskey <k> [log]

status = display power status
on = switch on
off = switch off
presskey = send key <k>, k='P' will press the power button
  
Use the log option to reditect the log to stdout. Otherwise /usr/share/openhab2/log/entertain_control.log will be used.

Please note:

The script reflects my scenario and doesn't have the target to be a universal implementation supporting all types of Android TVs. Is was tricky to get everything running, esp. the fact that the TV is accepting the ADB connection.
I'm not a bash expert, so maybe some optimizations and more specific error handling could be supplied.
Looking forward to any contribution. I could also provide some scripts for waking up a Apple-TV or controlling the Telekom Entertain Receiver. If you are interested feel free to cantact me.

Also check https://github.com/markus7017/AndroidTV_Control for control of Android TVs with openHAB.

HappySmartHoming & have fun, Markus
