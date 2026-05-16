Include HS.FHIRMeta

Class isc.ateam.fsub.FSUBRouterProcess Extends (Ens.BusinessProcess, isc.ateam.fsub.IFSUBLoggable)
{

/// Production setting that specifies FHIR Endpoint path
Parameter fhirEndpointSETTING = "FHIREndpoint";

Method OnRequest(pRequest As isc.ateam.fsub.msg.FSUBNotification, Output pResponse As Ens.Response) As %Status
{
	#dim sc As %Status = $$$OK
	try
	{
		// FHIRErrorNotification requests are initiated for logging purposes only
		if pRequest.%Extends(##class(isc.ateam.fsub.msg.FHIRErrorNotification).%ClassName(1))
		{
			#dim errorNotification As isc.ateam.fsub.msg.FHIRErrorNotification = pRequest
			#dim errorStatus As %Status = ""
			for i = 1:1:errorNotification.errors.Count()
			{
				#dim errorItem = errorNotification.errors.GetAt(i)
				set errorStatus = $case(errorStatus, "":errorItem.status, :$$$ADDSC(errorStatus, errorItem.status))
			}
			
			// log Subscription processing errors to Event Log
			Return errorStatus
		}
	
		do ..handleNotificationRequest(pRequest)
	}
	catch ex
	{
		Do ..LogInfo(ex.DisplayString())
		set sc = ex.AsStatus()
	}
	
	quit sc
}

/// Async responses from notification targets
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As HS.FHIRServer.Interop.Request, callresponse As HS.FHIRServer.Interop.Response, pCompletionKey As %String) As %Status
{
	do ..cleanUpQS()
	quit $$$OK
}

Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
	do ..cleanUpQS()
	quit pErrorStatus
}

/// Clean up QuickStream in request and response
ClassMethod cleanUpQS(callrequest As HS.FHIRServer.Interop.Request, callresponse As HS.FHIRServer.Interop.Response) [ Private ]
{
	try
	{
		if $isObject($get(callrequest)) && (callrequest.QuickStreamId '= "")
		{
			#dim qs As HS.SDA3.QuickStream = ##class(HS.SDA3.QuickStream).%OpenId(callrequest.QuickStreamId)
			if $isObject(qs) do qs.Clear()
		}
		
		if $isObject($get(callresponse)) && (callresponse.QuickStreamId '= "")
		{
			#dim qs2 As HS.SDA3.QuickStream = ##class(HS.SDA3.QuickStream).%OpenId(callresponse.QuickStreamId)
			if $isObject(qs2) do qs2.Clear()
		}
	}
	catch ex
	{
		$$$LOGSTATUS(ex.AsStatus())
	}
}

Method handleNotificationRequest(request As isc.ateam.fsub.msg.FSUBNotification) [ Private ]
{
	#Dim ep as %String = ""
	Try
	{
		Set j = ##class(%DynamicObject).%FromJSON(request.subscriptionStream)
		Set ep = j.channel.endpoint
	}
	Catch (pex) {}

	Do ..LogInfo("FSUBRouterProcess::handleNotificationRequest enter - resourceType=" _ request.resourceType _ ", subId=" _ request.subscriptionId _ ", endpoint=" _ ep)

	Try
	{
		if (request.subscriptionStream.Size = 0)
		{
			$$$ThrowError($$$GeneralError, "Empty subscriptionStream")
		}
		set request.subscriptionJson = ##class(%DynamicObject).%FromJSON(request.subscriptionStream)
		
		// as of now, "REST Hook" is the only supported channel type 
		if (request.subscriptionJson.channel.type '= "rest-hook")
		{
			$$$ThrowError($$$GeneralError, "Channel type not supported: " _ request.subscriptionJson.channel.type)
		}
		
		#dim payloadMimeType As %String = request.subscriptionJson.channel.payload
		if (payloadMimeType '= "") && (payloadMimeType '= "application/fhir+json") && (payloadMimeType '= "application/fhir+xml")
		{
			$$$ThrowError($$$GeneralError, "Unsupported MIME type for payload: " _ payloadMimeType)
		}
		
		#dim endpoint As %String = request.subscriptionJson.channel.endpoint
		#dim headerArray As %DynamicArray = request.subscriptionJson.channel.header
		
		// search for a HTTP Service Registry entry that has the full endpoint URL in its Alias field
		// note that an entry can have multiple aliases, e.g. IP address or domain name based URLs
		// #dim serviceEntry As HS.Registry.Service.HTTP = ##class(HS.Registry.Service.Abstract).EndPointForNameType(endpoint, "HTTP")
		#Dim serviceEntry as HS.Registry.Service.HTTP = ##class(HS.Registry.Service.HTTP).EndPointForURL(endpoint)
		if '$isObject(serviceEntry) 
		{
			$$$ThrowError($$$GeneralError, "Endpoint not found in the Service Registry: " _ endpoint)
		}
		else
		{
			Do ..LogInfo("FSUBRouterProcess::handleNotificationRequest - request will be forwarded to HTTP service " _ serviceEntry.Name _ " (" _ serviceEntry.EndPoint _ ")")
		}
		
		// search for a business operation with ServiceName=<name of the Service Registry entry we've just found>
		#dim operation As Ens.Config.Item = ..findConfigItemBySettingValue("ServiceName", serviceEntry.Name, $$$eHostTypeOperation)
		if '$isObject(operation) 
		{
			Do ..LogInfo("FSUBRouterProcess::handleNotificationRequest - cannot find Business Operation with ServiceName='" _ serviceEntry.Name _ "'")
			$$$ThrowError($$$GeneralError, "Cannot find Business Operation with ServiceName=""" _ serviceEntry.Name _ """")
		}
		else
		{
			Do ..LogInfo("FSUBRouterProcess::handleNotificationRequest - the request will be forwarded to Business Operation ='" _ operation.Name  _ "'")
		}
		
		
		if (payloadMimeType = "")
		{
			// REST request without payload, see https://www.hl7.org/fhir/r4/subscription.html#2.46.7.1
			Do ..LogInfo("FSUBRouterProcess::handleNotificationRequest - the request will be doesn't have payload")
			#dim noPayloadMessage As HS.FHIRServer.Interop.Request = ##class(HS.FHIRServer.Interop.Request).%New()
			set noPayloadMessage.Request.RequestMethod = "POST"
			
			// add custom headers to the request's AdditionalInfo array
			if (headerArray '= "") 
			{
				do ..addCustomHeadersToAdditionalInfo(headerArray, noPayloadMessage.Request)
			}
			
			// NB: send only ONE notification, even if there are multiple resources matching the current Subscription
			// see https://www.hl7.org/fhir/r4/subscription.html#2.46.7.1
			$$$ThrowOnError(..SendRequestAsync(operation.Name, noPayloadMessage,,, "FSUB No Payload Notification"))
		}
		else
		{
			Do ..LogInfo("FSUBRouterProcess::handleNotificationRequest - the request has some payload (" _ payloadMimeType _ ")")
			#dim schema As HS.FHIRServer.Schema = "" // we will need schema when transforming JSON to XML

			if (payloadMimeType = "application/fhir+xml")
			{
				Throw ##class(%Exception.General).%New(payloadMimeType _ " - not supported. Check subscription settings.")
			}
			
			// NB: the following CreateInstance() method expects the current production to be registered in the Installer Wizard for the current namespace (see HS.Util.Installer.ConfigItem class)
			//     hence it will throw an error if one changes to a different production after initial namespace setup

			Do ..LogInfo("FSUBRouterProcess::handleNotificationRequest - ready to create RestClient for BO ('" _ operation.Name _ "')")
			
			// iterate over the matching resources
			for i = 1:1:request.matchingResources.Count()
			{
				#dim resType As %String = request.matchingResources.GetAt(i).resourceType
				#dim resId As %String = request.matchingResources.GetAt(i).resourceId
				#dim payload As %Stream.Object = request.matchingResources.GetAt(i).resourceStream
				
				// #dim message As HS.FHIRServer.Interop.Request = clientObj.MakeRequest("PUT", payload,	"/" _ resType _ "/" _ resId, "")
				#Dim message as HS.FHIRServer.Interop.Request = ##class(HS.FHIRServer.Interop.Request).%New()
				#Dim innerRequest as HS.FHIRServer.API.Data.Request = ##class(HS.FHIRServer.API.Data.Request).%New()
				Set innerRequest.RequestMethod = "PUT"
				Set innerRequest.RequestPath = "/" _ resType _ "/" _ resId
				Set innerRequest.RequestFormatCode = "JSON"
				Set message.Request = innerRequest
				#Dim stream as HS.SDA3.QuickStream
				Set stream = ##class(HS.SDA3.QuickStream).%New()
				$$$ThrowOnError(payload.Rewind())
				$$$ThrowOnError(stream.CopyFrom(payload))
				$$$ThrowOnError(stream.Flush())
				$$$ThrowOnError(stream.%Save())
				Set message.QuickStreamId = stream.%Id()
				do message.Request.AdditionalInfo.RemoveAt("ServiceName")  // we don't actually need ServiceName to be passed in requests
				
				// add custom headers to the request's AdditionalInfo array
				if (headerArray '= "") do ..addCustomHeadersToAdditionalInfo(headerArray, message.Request)
				
				// send *async* request to the operation (async requests are not supported by HS.FHIRServer.RestClient.Interop as of 2022.1, so calling SendRequestAsync "manually")

				Do ..LogInfo("FSUBRouterProcess::handleNotificationRequest - ready to forward a request with payload to '" _ operation.Name _ "'")
				$$$ThrowOnError(..SendRequestAsync(operation.Name, message,,, "FSUB Notification With Payload"))

			} // for
		}
	}
	Catch (ex)
	{
		Do ..LogInfo("FSUBRouterProcess::handleNotificationRequest error - " _ ex.DisplayString())
		Throw ex
	}
}

/// Add custom headers to the request's AdditionalInfo array.
ClassMethod addCustomHeadersToAdditionalInfo(headerArray As %DynamicArray, request As HS.FHIRServer.API.Data.Request) [ Private ]
{
	#dim iter As %Iterator.Object = headerArray.%GetIterator()
	#dim entry As %String
	#dim keyPrefix As %String = "HEADER:"
	while iter.%GetNext(.key, .entry)
	{
		do request.AdditionalInfo.SetAt($zstrip($piece(entry, ":", 2), "<>W"), keyPrefix _ $zstrip($piece(entry, ":", 1), "<>W"))
	}
}

/// Find a business host by setting's name/value pair.
/// <var>businessType</var> can be $$$eHostTypeService, $$$eHostTypeProcess or $$$eHostTypeOperation.
/// Empty <var>businessType</var> means that type does not matter.
/// If <var>enabledOnly</var> is 1 then search enabled hosts only.
ClassMethod findConfigItemBySettingValue(settingName As %String, settingValue As %String, businessType As %String(VALUELIST=",1,2,3") = "", enabledOnly As %Boolean = {$$$NO}) As Ens.Config.Item
{
	#dim prod As Ens.Config.Production = ..getCurrentProduction()
	if '$isObject(prod) quit ""

	// loop through production elements
	#dim result As Ens.Config.Item = ""
	for i = 1:1:prod.Items.Count()
	{
		#dim item As Ens.Config.Item = prod.Items.GetAt(i)
		#Dim setting as Ens.Config.Setting
		for j = 1:1:item.Settings.Count()
		{
			Set setting = item.Settings.GetAt(j)
			If ((setting.Name = settingName) && (setting.Value = settingValue))
			{
				return item
			}
		}

	#; 	if '$isObject(item)
	#; 			|| ((businessType '= "") && (item.BusinessType() '= businessType))
	#; 			|| (enabledOnly && 'item.Enabled)
	#; 	{
	#; 		continue
	#; 	}
		
	#; 	// loop through settings
	#; 	do item.PopulateModifiedSettings()
	#; 	#dim ind As %String = ""
	#; 	for
	#; 	{
	#; 		#dim setting = item.ModifiedSettings.GetNext(.ind)
	#; 		if (ind = "") quit

	#; 		if (setting.Name = settingName)
	#; 		{
	#; 			if ($zstrip(setting.Value, "<>W") = $zstrip(settingValue, "<>W")) set result = item
	#; 			quit
	#; 		}
	#; 	} // for

	#; 	if $isObject(result) quit
	} // for
	//quit result
	Return ""
}

ClassMethod getCurrentProduction() As Ens.Config.Production
{
	#dim prodName As %String
	if '##class(Ens.Director).IsProductionRunning(.prodName) quit ""
	
	#dim sc As %Status
	#dim prod As Ens.Config.Production = ##class(Ens.Config.Production).%OpenId(prodName,, .sc)
	$$$ThrowOnError(sc)  // highly unlikely
	
	quit prod
}

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}

