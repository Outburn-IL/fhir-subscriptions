Class Outburn.Fume.Subscriptions.Queue Extends %Persistent
{
Property Content as %String(MAXLEN="");

Storage Default
{
<Data name="QueueDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Content</Value>
</Value>
</Data>
<DataLocation>^Outburn.Fume.Subscri2352.QueueD</DataLocation>
<DefaultData>QueueDefaultData</DefaultData>
<IdLocation>^Outburn.Fume.Subscri2352.QueueD</IdLocation>
<IndexLocation>^Outburn.Fume.Subscri2352.QueueI</IndexLocation>
<StreamLocation>^Outburn.Fume.Subscri2352.QueueS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
