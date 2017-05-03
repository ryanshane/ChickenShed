####################################################################################################
# Chicken Door
# (*) Save status to file every 15th minute
# (*) Warn when the water is too low
# (*) Open door at sunrise based on location (checks status and emails confirmation)
# (*) Close door at sunset + 1hr based on location (checks status and emails confirmation)
#
# Dependencies
# (*) IP Webcam Android App (free): exposes an android's sensors as a REST endpoint
# (*) CalcSunTimes.dll -- helper to calculate sunrise and sunset based on latitude and longitude
#
# Note:
# (*) Commands sent to the ChickenShed (esp8266 wifi chip) are done using VBScript beacuse
#     .NET objects seem to have an issue sending web requests to it (Protocol violation exceptions). 
#     This might be to do with the way the LUA / nodeMCU web server handles the connection.
#
# Author: Ryan Steller
# Blog: https://debugtopinpoint.wordpress.com
####################################################################################################

Add-Type -Path "C:\Users\ryans\Google Drive\Development\ChickenDoor\Powershell job\CalcSunTimes.dll"

$lastLogMinute = -1
$lastDoorAction = -1

$waterThreshold = 0.5 # Low water warning threshold (kg)
$waterEmpty = 0.0 # Water empty level
$waterConatinerWeight = 0.5 # (the container weighs about 0.45kg but there might have been some dirt kicked into it)
$lastWaterWarning = [DateTime]::MinValue

# Time to open and close depends on the sunrise and sunset times, which can be calculated from latitude and longitude. This works with DST.
$lat = new-object SunTimes.SunTimes+LatitudeCoords(-37, 48, 51, [SunTimes.SunTimes+LatitudeCoords+Direction]::North)
$lon = new-object SunTimes.SunTimes+LongitudeCoords(144, 57, 47, [SunTimes.SunTimes+LongitudeCoords+Direction]::East)

# The below IP addresses will need to be configured as static in your router
$chickenShedUrl = "http://192.168.1.7"
$ipWebcamUrl = "http://192.168.1.8:8080"

# Gmail account for sending email notifications
$gmailUsername = "gmailaccountname" # account name without the @gmail.com
$gmailPass = "gmailpassword"

$appFolder = "C:\ChickenDoor\Powershell job"
$archiveFolder = "C:\Users\yyy\google drive\ChickenShed" # Auto sync to google drive to check back on status history

$debugMode = $false

# Send email from Gmail account with a current photo attached (optionally use flash)
function SendEmail($subject, $body, $to, $useFlash) {
    write-host -f green "Send email to" $to "(" $subject ")"
	
    if($useFlash -eq $true) {
        Invoke-RestMethod -Uri ($ipWebcamUrl + "/enabletorch")
        Start-Sleep -m 100
    }
    $wc = New-Object System.Net.WebClient   
    try{
        $wc.DownloadFile($ipWebcamUrl + "/photoaf.jpg", $appFolder + "\chickenshedphoto.jpg")
    }
    catch {}
    if($useFlash -eq $true) {
        Invoke-RestMethod -Uri ($ipWebcamUrl + "/disabletorch")
        Start-Sleep -m 500
        Invoke-RestMethod -Uri ($ipWebcamUrl + "/disabletorch")
    }
    
    $EmailFrom = "CHICKENSHED <gmailaccountname@gmail.com>"
    $EmailTo = $to
    $Subject = $subject
    $Body = $body
    $SMTPServer = "smtp.gmail.com"
    $SMTPClient = New-Object Net.Mail.SmtpClient($SmtpServer, 587)
    $SMTPClient.UseDefaultCredentials = $false
    $SMTPClient.EnableSsl = $true
    $SMTPClient.Credentials = New-Object System.Net.NetworkCredential($gmailUsername, $gmailPass);
 
    $emailMessage = New-Object System.Net.Mail.MailMessage
    $emailMessage.From = $EmailFrom
    $emailMessage.To.Add($EmailTo)
    $emailMessage.Subject = $Subject
    $emailMessage.Body = $Body
    $emailMessage.Attachments.Add($appFolder + "\chickenshedphoto.jpg")
    try{
        $SMTPClient.Send($emailMessage)
    }
    catch {}
    write-host -f green "- Done"
}

write-host -f green "Started" (Get-Date -Format g)

while($true) {
    $dtNow = Get-Date

    # SAVE STATUS (every 15th minute)
    if($dtNow.Minute % 15 -eq 0 -and $lastLogMinute -ne $dtNow.Minute -or $debugMode) {

        $succeeded = $false
        $attempt = 0

        # Attempt to check the status until it looks valid. E.g sometimes the water reading is in the minuses and therefore isn't valid
        while(-not $succeeded -and $attempt -lt 6) {
            $lastLogMinute = $dtNow.Minute
            write-host -f green "Get status as json..." (Get-Date -Format g)
            invoke-expression ("cmd /C cscript " + $appFolder + "\GetStatusAsJson.vbs """ + $appFolder + """ """ + $archiveFolder + """ """ + $chickenShedUrl + """")

            # Save photo
            write-host -f green "Save photo..."
            $wc = New-Object System.Net.WebClient
            try{
                Invoke-RestMethod -Uri ($ipWebcamUrl + "/nofocus") -TimeoutSec 3
		        Start-Sleep -m 100
		        Invoke-RestMethod -Uri ($ipWebcamUrl + "/focus") -TimeoutSec 3
		        Start-Sleep -m 1500
                $imgFileName = "Photo_" + (Get-Date).ToString("yyyy-MM-dd-THH-mm-ss") + ".jpg"
                $wc.DownloadFile($ipWebcamUrl + "/photoaf.jpg", $appFolder + "\Status\" + $imgFileName)
                $wc.DownloadFile($ipWebcamUrl + "/photoaf.jpg", $archiveFolder + "\Status\" + $imgFileName)
            }
            catch {
                write-host -f green "Could not communicate with the camera."
            }

            # Now check the status for anything to warn about like water level
            write-host -f green "Check status for anything to warn about..."
            $files = Get-ChildItem -Path ($appFolder + "\Status") -Filter "*.json" | Sort-Object LastAccessTime -Descending | Select-Object -First 1
            if($files.Length -gt 0) {
                $text = Get-Content -Path $files[0].FullName;
                $j = ConvertFrom-Json $text;

                # Ensure the raw value is valid
                if($j.WaterKg -gt 0) {
                    $j.WaterKg = $j.WaterKg - $waterConatinerWeight
                    write-host -f green "Status is valid"
                    $succeeded = $true

                    # Warn if the water level is too low
                    if($j.WaterKg -lt $waterThreshold -and ($dtNow-$lastWaterWarning).TotalMinutes -gt 60) {
                        $lastWaterWarning = $dtNow
                        write-host -f yellow "Send low water level warning as it dropped below the threshold (WaterKg:" $j.WaterKg ", Threshold: $waterThreshold)"
                        if($j.WaterKg -lt $waterEmpty) {
                            $body = "The water is EMPTY!"
                            SendEmail -to me@gmail.com -subject 'ChickenShed: EMPTY water warning' -body $body -useFlash $false
                        }
                        else {
                            $body = "The water level is low: " + $j.WaterKg + "kg."
                            SendEmail -to me@gmail.com -subject 'ChickenShed: Low water warning' -body $body -useFlash $false
                        }
                    }
                    else {
                        write-host -f green "Water level is ok: " $j.WaterKg "kg."
                    }
                }
                else {
                    write-host -f green "Status was not valid (water level in the minuses). Trying again..."
                }
            }
        }
        if(-not $succeeded) {
            $body = "An invalid status occurred after 5 retries (water: " + $j.WaterKg + "kg)"
            SendEmail -to me@gmail.com -subject 'ChickenShed: status error' -body $body -useFlash $false
        }
    }

    # OPEN / CLOSE DOOR times are calculated based on the latitude and longitude (e.g. Melbourne)
    $sunrise = [SunTimes.SunTimes]::Instance.GetSunriseTime($lat, $lon, [DateTime]::Now);
    $sunset = [SunTimes.SunTimes]::Instance.GetSunsetTime($lat, $lon, [DateTime]::Now);
    $sunrise = $sunrise.AddMinutes(0);
    $sunset = $sunset.AddMinutes(60); # 1 hour after sun set to be sure they're all in
    $timeToOpenDoor = ($dtNow.Hour -eq $sunrise.Hour -and $dtNow.Minute -eq $sunrise.Minute)
    $timeToCloseDoor = ($dtNow.Hour -eq $sunset.Hour -and $dtNow.Minute -eq $sunset.Minute)
    
    $doorActionTimeStamp = "" + $dtNow.Hour + " " + $dtNow.Minute	
    #write-host -f Gray "Check" $doorActionTimeStamp

    if($timeToOpenDoor -or $timeToCloseDoor -and $lastDoorAction -ne $doorActionTimeStamp) {
        $lastDoorAction = $doorActionTimeStamp

        write-host -f green "Time to open or close"
		write-host -f Gray "Calculated sunrise / sunset times today: Sunrise: $sunrise, Sunset: $sunset"

        $succeeded = $false
        $attempt = 0

        # Attempt to send the OpenDoor command until the status reflects that it worked
        while(-not $succeeded -and $attempt -lt 11) {
            $attempt += 1
                        
            if($timeToOpenDoor) {
                invoke-expression ("cmd /C cscript " + $appFolder + "\OpenDoor.vbs """ + $appFolder + """ """ + $archiveFolder + """ """ + $chickenShedUrl + """")
                write-host -f green "Send OpenDoor command" (Get-Date -Format g)
            }
            elseif($timeToCloseDoor) {
                invoke-expression ("cmd /C cscript " + $appFolder + "\CloseDoor.vbs """ + $appFolder + """ """ + $archiveFolder + """ """ + $chickenShedUrl + """")
                write-host -f green "Send CloseDoor command" (Get-Date -Format g)
            }

            Start-Sleep -s 5

            write-host -f green "Check status to see if the command worked"

            # Check status to see if it worked
            invoke-expression ("cmd /C cscript " + $appFolder + "\ChickenDoorStatusCheck.vbs """ + $appFolder + """ """ + $archiveFolder + """ """ + $chickenShedUrl + """")
            $files = Get-ChildItem -Path $appFolder -Filter "GetStatusAsJson.json" | Where-Object {$_.LastWriteTime -gt (Get-Date).AddMinutes(-5)}
            if($files.Length -gt 0) {
                $text = Get-Content -Path $files[0].FullName;
                $j = ConvertFrom-Json $text;
                if($j.Status -ne "Idle") {
                    # Command succeeded.
                    write-host -f green "- Command succeeded."
                    $succeeded = $true

                    # Send email notification (dependent on the Send-Email cmdlet (SBEmail)
                    if($timeToOpenDoor) {
                        SendEmail -to me@gmail.com -subject 'ChickenShed: Door open' -body 'Door open successfully started.' -useFlash $true
                    }
                    elseif($timeToCloseDoor) {
                        SendEmail -to me@gmail.com -subject 'ChickenShed: Door close' -body 'Door close successfully started.' -useFlash $true
                    }
                    
                }
                else {
                    write-host -f green "- Command did not succeed. Retry..."
                }
            }
            else {
                write-host -f green "- Check status command did not succeed and therefore the success of the move command can't be determined. Retry..."
            }

        }
        if(-not $succeeded) {
            write-host -f red "* ERROR: Failed to operate the door!"

            # Send email notification (dependent on the Send-Email cmdlet (SBEmail)
            if($timeToOpenDoor) {
                SendEmail -to me@gmail.com -subject 'ChickenShed: Door open FAILED' -body 'Door open FAILED to start.' -useFlash $false
            }
            elseif($timeToCloseDoor) {
                SendEmail -to me@gmail.com -subject 'ChickenShed: Door close FAILED' -body 'Door close FAILED to start.' -useFlash $false
            }

        }
        
    }
    
    Start-Sleep -s 1 # Check the time every second
}

