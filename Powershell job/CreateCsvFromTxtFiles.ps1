$root = "C:\ChickenDoor\Status"
$destination = "C:\ChickenDoor"
$files = Get-ChildItem -Path $root -Filter *.json


$results = @()

ForEach ($file in $files){
    write-host -f green $file.FullName;

    $text = Get-Content -Path $file.FullName;
    if(-Not $text.Contains("Error.")) {
        $j = ConvertFrom-Json $text;

        $dt = $file.CreationTime
        $date = $dt.ToString("yyyy-M-dd")
        $time = $dt.ToString("HH:mm")

        $details = @{            
                        Date = $date
                        Time = $time
                        Status = $j.Status
                        Door = $j.Door
                        WaterKg = $j.WaterKg
                    }
        $results += New-Object PSObject -Property $details 
    }
}
$results | export-csv -Path (Join-Path $destination "out.csv") -NoTypeInformation