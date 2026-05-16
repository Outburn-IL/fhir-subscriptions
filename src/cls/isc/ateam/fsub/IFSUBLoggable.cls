include Ensemble

Class isc.ateam.fsub.IFSUBLoggable Extends %RegisteredObject
{
Method LogInfo(value as %String)
{
    $$$TRACE(value)
    Set msg = ##class(FSUBLog).%New()
    Set msg.Message = value
    Do msg.%Save()
}
}
