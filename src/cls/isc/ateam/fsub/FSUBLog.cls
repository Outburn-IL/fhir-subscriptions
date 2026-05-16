Class isc.ateam.fsub.FSUBLog Extends %Persistent
{
Property Message as %String(MAXLEN="");


Storage Default
{
<Data name="FSUBLogDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Message</Value>
</Value>
</Data>
<DataLocation>^isc.ateam.fsub.FSUBLogD</DataLocation>
<DefaultData>FSUBLogDefaultData</DefaultData>
<IdLocation>^isc.ateam.fsub.FSUBLogD</IdLocation>
<IndexLocation>^isc.ateam.fsub.FSUBLogI</IndexLocation>
<StreamLocation>^isc.ateam.fsub.FSUBLogS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
