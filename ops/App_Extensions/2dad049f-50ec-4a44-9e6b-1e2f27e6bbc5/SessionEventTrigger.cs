using System;
using System.Text;
using System.Threading.Tasks;
using ScreenConnect;

public class SessionEventTriggerAccessor : IAsyncDynamicEventTrigger<SessionEventTriggerEvent>
{
	public async Task ProcessEventAsync(SessionEventTriggerEvent sete)
	{
		if (sete.Event.EventType == SessionEventType.Connected && sete.Connection.ProcessType == ProcessType.Guest && sete.Session.SessionType == SessionType.Access)
			await DynamicCustomPropertiesUtil.SendCustomPropertyRefreshCommand(
				sete.Session.SessionID, 
				await DynamicCustomPropertiesUtil.CreateCommandToRefreshCustomProperties(
					sete.Session.SessionID
				),
				await WebResources.GetStringAsync("DynamicCustomProperty.RefreshCommand.HostName")
			);
		
		if (sete.Event.EventType == SessionEventType.RanCommand && sete.Event.Data.StartsWith("CUSTOMPROPERTYCOMMANDS-RESPONSE/2"))
		{
			await DynamicCustomPropertiesUtil.ProcessCommandResultAndUpdateCustomProperties(sete.Session.SessionID, sete.Event.Data);
			//await DynamicCustomPropertiesUtil.DeleteOldCustomPropertyCommands(sete);
		}
	}
}
