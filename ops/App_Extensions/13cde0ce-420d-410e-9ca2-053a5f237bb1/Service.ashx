<%@ WebHandler Language="C#" Class="RemoteDiagnosticToolkitService" %>

using System;
using System.Linq;
using System.Security;
using System.Web;
using System.Threading.Tasks;
using Nito.AsyncEx;
using ScreenConnect;

[ActivityTrace]
public class RemoteDiagnosticToolkitService : WebServiceBase
{
	public async Task AddDiagnosticEventToSession(Guid sessionID, string data) =>
		await RemoteDiagnosticToolkitService.ExecuteSessionProcAsync(
			sessionID,
			await PermissionInfo.GetAddEventPermissionNameAsync(SessionEventType.QueuedCommand, new AsyncLazy<SessionEventType>(() => default)),
			async (session, _) => await SessionManagerPool.Demux.AddSessionEventAsync(session.SessionID, new()
			{
				EventType = SessionEventType.QueuedCommand,
				Data = data,
			})
		);

	public async Task DeleteDiagnosticCommandEvents(Guid sessionID, Guid? connectionID, Guid eventID, SessionEventType eventType) =>
		await RemoteDiagnosticToolkitService.ExecuteSessionProcAsync(
			sessionID,
			await PermissionInfo.GetAddEventPermissionNameAsync(SessionEventType.DeletedEvent, ServerExtensions.CreateAsyncLazy(async () => eventType)),
			async (session, _) => await SessionManagerPool.Demux.AddSessionEventAsync(session.SessionID, new()
			{
				EventType = SessionEventType.DeletedEvent,
				ConnectionID = connectionID.GetValueOrDefault(),
				CorrelationEventID = eventID,
			})
		);

	static async Task ExecuteSessionProcAsync(Guid sessionID, string permissionName, Func<Session, string, Task> proc)
	{
		var user = HttpContext.Current.User;
#if SC_23_3
		var permissionSet = await Permissions.GetForUserAsync(user);
#else
		var permissionSet = await Permissions.GetForUserAsync(HttpContext.Current);
#endif
// TODO: Change SC_100_0 version check when the fix for SCP_37371 is released
#if SC_100_0
		var sessionGroupPathFilterForPermissions = Permissions.GetSessionGroupPathFilterForPermissions(permissionSet, permissionName);
#else
		var sessionGroupPathFilterForPermissions = Permissions.ComputeSessionGroupPathFilterForPermissions(permissionSet, permissionName);
#endif
		var sessionGroups = await SessionManagerPool.Demux.GetSessionGroupsAsync(sessionGroupPathFilterForPermissions);
		var variables = await ServerExtensions.GetStandardVariablesAsync(user);

		if (!await sessionGroups.ToAsyncEnumerable().AnyAwaitAsync(async it => await SessionManagerPool.Demux.IsSessionInGroupAsync(sessionID, it.Name.ToSingleElementArray(), variables)))
			throw new SecurityException("Session doesn't exist, or you do not have permission to perform this operation on it");

		await proc(await SessionManagerPool.Demux.DemandSessionAsync(sessionID), user.GetUserDisplayNameWithFallback());
	}
}


