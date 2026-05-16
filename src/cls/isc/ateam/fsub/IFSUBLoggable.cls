include Ensemble

Class isc.ateam.fsub.IFSUBLoggable [abstract]
{
Method LogInfo(value as %String)
{
    $$$TRACE(value)
    Set msg = ##class(FSUBLog).%New()
    Set msg.Message = value
    $$$ThrowOnError(msg.%Save())
}

ClassMethod StaticLogInfo(value as %String)
{
    $$$TRACE(value)
    Set msg = ##class(FSUBLog).%New()
    Set msg.Message = value
    $$$ThrowOnError(msg.%Save())
}

}
