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
oXMLHTTP.Open "GET", WScript.Arguments.Item(2) & "/CloseDoor", False
oXMLHTTP.Send

If oXMLHTTP.Status = 200 Then
    Set oStream = CreateObject("ADODB.Stream")
    oStream.Open
    oStream.Type = 1
    oStream.Write oXMLHTTP.responseBody
    oStream.SaveToFile WScript.Arguments.Item(0) & "\CloseDoor.html"
    oStream.Close
End If
