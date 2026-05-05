Class SUBSCRIPTIONSPKG.FoundationProduction Extends Ens.Production [ Not ProcedureBlock ]
{

XData ProductionDefinition
{
<Production Name="SUBSCRIPTIONSPKG.FoundationProduction" LogGeneralTraceEvents="false">
  <Description></Description>
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="isc.ateam.fsub.FSUBRouterProcess" Category="" ClassName="isc.ateam.fsub.FSUBRouterProcess" PoolSize="1" Enabled="false" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="isc.ateam.fsub.bo.RESTHookOperation" Category="" ClassName="isc.ateam.fsub.bo.RESTHookOperation" PoolSize="1" Enabled="false" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
  </Item>
</Production>
}

}
