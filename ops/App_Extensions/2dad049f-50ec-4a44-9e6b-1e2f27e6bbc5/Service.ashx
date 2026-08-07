<%@ WebHandler Language="C#" Class="DynamicCustomPropertiesService" %>
<%@ Assembly Src="DynamicCommandBuilder.cs" %>

using System;
using System.Web;
using System.Text;
using System.Linq;
using System.Net;
using System.Threading.Tasks;
using System.Globalization;
using System.Collections.Generic;
using System.Collections.Specialized;

using ScreenConnect;

public class DynamicCustomPropertiesService : WebServiceBase
{
	public async Task AddRefreshCustomPropertiesCommand(object sessionGroupPathPartsOrName, IList<Guid> sessionIDs)
	{
		await this.DemandPermissionsAsync(
			sessionGroupPathPartsOrName,
			sessionIDs,
			PermissionInfo.RunCommandOutsideSessionPermission,
#if SC_23_3
			await Permissions.GetForUserAsync(HttpContext.Current.User)
#else
			await Permissions.GetForUserAsync(HttpContext.Current)
#endif
		);

		var userDisplayName = HttpContext.Current.User.GetUserDisplayNameWithFallback();
		var sessionInfos = await SessionManagerPool.Demux.GetSessionsAsync(sessionIDs.ToArray());

		foreach (var session in sessionInfos)
		{
			var commandData = await DynamicCustomPropertiesUtil.CreateCommandToRefreshCustomProperties(session.SessionID);
			
			await DynamicCustomPropertiesUtil.SendCustomPropertyRefreshCommand(
				session.SessionID, 
				commandData,
				userDisplayName
			);
		}
	}

	async Task DemandPermissionsAsync(object sessionGroupPathPartsOrName, IList<Guid> sessionIDs, string permissionName, PermissionSet permissions)
	{
		var sessionGroupPath = SessionGroupPath.FromParts(sessionGroupPathPartsOrName.EnsureStringArray());
		var variables = await ServerExtensions.GetStandardVariablesAsync(HttpContext.Current.User);

		var areSessionsInGroup = await SessionManagerPool.Demux.AreSessionsInGroupAsync(
			sessionIDs,
			sessionGroupPath,
			Permissions.ComputeSessionGroupPathFilterForPermissions(permissions, permissionName),
			variables
		);

		if (!areSessionsInGroup)
			throw new InvalidOperationException("Session not in specified group, or you do not have permission to perform this operation on it");
	}

	[DemandPermission(PermissionInfo.AdministerPermission)]
	public async Task SaveCustomPropertyCommands(string newCustomPropertiesCommands)
	{
		var runtime = await ExtensionRuntime.TryGetExtensionRuntimeAsync(ExtensionContext.Current.ExtensionID);
		if (runtime == null)
			throw new InvalidOperationException("Extension runtime not found.");

		Dictionary<string, string> oldSettingValues = runtime.AllSettingsValues.ToDictionary();

		oldSettingValues["CustomPropertyCommandListJsonBlob"] = newCustomPropertiesCommands;
#if SC_23_6
		await ExtensionRuntime.SaveExtensionSettingValuesAsync(ExtensionContext.Current.ExtensionID, oldSettingValues);
#else
		ExtensionRuntime.SaveExtensionSettingValues(ExtensionContext.Current.ExtensionID, oldSettingValues);
#endif
	}
}
