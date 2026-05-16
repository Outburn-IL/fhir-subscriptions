Class Outburn.Fume.Subscriptions.Test.TestBusinessOperatons Extends %UnitTest.TestCase
{
Method OnBeforeAllTests() As %Status
{
  Set ^UnitTestRoot = "/tmp"
  Return $$$OK
}

Method TestBusinessOperationWithPayload()
{

    #Dim bo as isc.ateam.fsub.bo.RESTHookOperation
    Set bo = ##class(isc.ateam.fsub.bo.RESTHookOperation).%New("REST Hook: with-payload")
    #Dim request as HS.FHIRServer.Interop.Request
    Set request = ##class(HS.FHIRServer.Interop.Request).%New()
    Set innerRequest = ##class(HS.FHIRServer.API.Data.Request).%New()
    Set innerRequest.RequestPath = "/Patient/123"
    Set innerRequest.RequestMethod = "PUT"
    Set request.Request = innerRequest
    Set innerRequest.RequestFormatCode = "JSON"
    #Dim stream as HS.SDA3.QuickStream
    Set stream = ##class(HS.SDA3.QuickStream).%New()
    $$$ThrowOnError(stream.Write("{""resourceType"":""Patient""}}"))
    $$$ThrowOnError(stream.Flush())
    $$$ThrowOnError(stream.%Save())
    Set request.QuickStreamId = stream.%Id()
    Set status = bo.DispatchRequest(request, .pResponse)
    Do $$$AssertTrue(pResponse.Response.Status = "200 OK")
    $$$ThrowOnError(status)
}

Method TestBusinessOperationWithoutPayload()
{
    #Dim bo as isc.ateam.fsub.bo.RESTHookOperation
    Set bo = ##class(isc.ateam.fsub.bo.RESTHookOperation).%New("REST Hook: no-payload")
    #Dim request as HS.FHIRServer.Interop.Request
    Set request = ##class(HS.FHIRServer.Interop.Request).%New()
    Set innerRequest = ##class(HS.FHIRServer.API.Data.Request).%New()
    Set request.Request = innerRequest
    Set innerRequest.RequestMethod = "POST"
    Set status = bo.DispatchRequest(request, .pResponse)
    Do $$$AssertTrue(pResponse.Response.Status = "200 OK")
    $$$ThrowOnError(status)
}
}
