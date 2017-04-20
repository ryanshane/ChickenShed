'-----------------------------------------
' Expected arguments:
' (0) appFolder: target location for outputting files like responses to REST calls
' (1) archiveFolder: a second location for the above. This might be used to save to a second location like a folder that synchs with g-drive for example
' (2) chickenShedUrl: The url to the chicken shed (esp8266's IP address). This is the base path against which REST calls are made to check status / move the door
'-----------------------------------------
on error resume next
Dim oXMLHTTP
Dim oStream

Set oXMLHTTP = CreateObject("MSXML2.XMLHTTP.3.0")
oXMLHTTP.Open "GET", WScript.Arguments.Item(2) & "/GetStatusAsJson", False
oXMLHTTP.Send

If oXMLHTTP.Status = 200 Then
    Set oStream = CreateObject("ADODB.Stream")
    oStream.Open
    oStream.Type = 1
    oStream.Write oXMLHTTP.responseBody
    oStream.SaveToFile WScript.Arguments.Item(0) & "\Status\GetStatusAsJson-" & iso8601Date(Now) & ".json", 2
	oStream.SaveToFile WScript.Arguments.Item(1) & "\Status\GetStatusAsJson-" & iso8601Date(Now) & ".json", 2
    oStream.Close
End If

Function iso8601Date(dt)
    s = datepart("yyyy",dt) & "-"
    s = s & RIGHT("0" & datepart("m",dt),2) & "-"
    s = s & RIGHT("0" & datepart("d",dt),2) & "-"
    s = s & "T"
    s = s & RIGHT("0" & datepart("h",dt),2) & "-"
    s = s & RIGHT("0" & datepart("n",dt),2) & "_"
    s = s & RIGHT("0" & datepart("s",dt),2) & "_"
    iso8601Date = s
End Function