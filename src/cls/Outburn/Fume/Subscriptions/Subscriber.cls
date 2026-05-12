Class Outburn.Fume.Subscriptions.Subscriber Extends %CSP.REST
{

/// THE SAME AS isc.ateam.fsub.mock.DummyRESTHookHandler

Parameter standardHttpHEADERS = {$lb("ACCEPT_ENCODING", "CONTENT_LENGTH", "HOST", "REFERER", "USER_AGENT", "ACCEPT")};

ClassMethod noPayload() As %Status
{
	do ..logRequest()
	quit $$$OK
}

ClassMethod withPayload(requestPath As %String) As %Status
{
	do ..logRequest()
	
	// output some headers that are expected from Update operation
	#dim %response As %CSP.Response
	do %response.SetHeader("CONTENT-LOCATION", "http://tempuri.org/fhir/" _ requestPath _ "/_history/1")
	do %response.SetHeader("ETAG", "W/""1""")
	do %response.SetHeader("LOCATION", "http://tempuri.org/fhir/" _ requestPath _ "/_history/1")
	set %response.Expires = 0

	quit $$$OK
}

ClassMethod logRequest() [ Private ]
{
	#dim %request As %CSP.Request
	if $isObject(%request.Content)
	{
		Do ..logRequestContent(%request.Content)
	}
}

ClassMethod logRequestContent(stream As %Stream.Object) [ Private ]
{
	#Dim content As %String = stream.Read(stream.Size)
    Set queue = ##class(Outburn.Fume.Subscriptions.Queue).%New()
    Set queue.Content = content
    Do queue.%Save()
}

ClassMethod onGet() as %Status
{
    Write "healthy"
    Return $$$OK
}

XData UrlMap
{
<Routes>
    <Route Url="" Method="GET" Call="onGet" />
    <Route Url="/" Method="GET" Call="onGet" />
	<Route Url="/no-payload" Method="POST" Call="noPayload"/>
	<Route Url="/with-payload/(.*)" Method="PUT" Call="withPayload"/>
</Routes>
}

}
