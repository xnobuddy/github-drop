using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.Text;
using System.Linq;
using ScreenConnect;

public class DynamicCustomPropertiesUtil
{
	static string customPropertyFormatterPrefix = "$SCCustomProperty";
	static string startCustomPropertyDelimiter = "StartCustomProperty";
	static string endCustomPropertyDelimiter = "EndCustomProperty";
	
	public static async Task<string> CreateCommandToRefreshCustomProperties(Guid sessionID)
	{
		var commands = JsonSerializer.Instance.Deserialize<string[]>(ExtensionContext.Current.GetSettingValue("CustomPropertyCommandListJsonBlob"));

		StringBuilder commandData = new StringBuilder();
		
		commandData.AppendLine("#!ps");
		commandData.AppendLine("#maxlength=500000");
		commandData.AppendLine("#timeout=900000");
		commandData.AppendLine("#CUSTOMPROPERTYCOMMANDS-REQUEST/2");
		commandData.AppendLine("echo \"CUSTOMPROPERTYCOMMANDS-RESPONSE/2\"");
		commandData.AppendLine("echo \"\"");
		commandData.AppendLine("$Variables");
		
		for (var i = 0; i < commands.Length; i++)
			if (!string.IsNullOrEmpty(commands[i])) {
				commandData.AppendLine("echo StartCustomProperty" + (i));
				commandData.AppendLine(commands[i]);
				commandData.AppendLine("echo EndCustomProperty" + (i));
			}
			
		string formattedCommandData = commandData.ToString();
		
		if (formattedCommandData.Contains(DynamicCustomPropertiesUtil.customPropertyFormatterPrefix))
			formattedCommandData = await DynamicCustomPropertiesUtil.FormatValuesInCommand(sessionID, formattedCommandData);
		
		return formattedCommandData;
	}
	
	public static async Task SendCustomPropertyRefreshCommand(Guid sessionID, string commandData, string byHost)
	{
		await SessionManagerPool.Demux.AddSessionEventAsync(
			sessionID, 
			new SessionEvent
			{
				EventType = SessionEventType.QueuedCommand,
				Host = byHost,
				Data = commandData
			}
		);
	}
	
	public static async Task ProcessCommandResultAndUpdateCustomProperties(Guid sessionID, string commandResponseData)
	{
		var session = await SessionManagerPool.Demux.GetSessionAsync(sessionID);
		
		List<string> newProperties = new List<string>();
		List<string> oldProperties = (session.CustomPropertyValues ?? Array.Empty<string>()).ToList();
		while (oldProperties.Count < 8)
			oldProperties.Add(string.Empty);
		
		for(int i = 0; i < 8; i++)
		{
			var startMarker = startCustomPropertyDelimiter + i;
			var endMarker = endCustomPropertyDelimiter + i;
			var startMarkerIndex = commandResponseData.IndexOf(startMarker);
			if (startMarkerIndex >= 0)
			{
				var startIndex = startMarkerIndex + startMarker.Length;
				var endIndex = commandResponseData.IndexOf(endMarker, startIndex);
				if (endIndex < 0)
				{
					newProperties.Add(oldProperties[i]);
					continue;
				}

				var result = commandResponseData.Substring(startIndex, endIndex - startIndex);
				result = result.Trim('\r', '\n');
				
				if (string.IsNullOrEmpty(result) && ExtensionContext.Current.GetSettingValue("ShouldPreservePropertyWithEmptyResult") == "true")
					newProperties.Add(oldProperties[i]);
				else
					newProperties.Add(result);
			}
			else
				newProperties.Add(oldProperties[i]);
		}
		
		await DynamicCustomPropertiesUtil.UpdateSessionCustomPropertiesAsync(session, newProperties.ToArray());
	}
	
	static async Task UpdateSessionCustomPropertiesAsync(Session session, string[] newCustomProperties)
	{
		if (session == null)
			throw new InvalidOperationException("Session not found.");
			
		await SessionManagerPool.Demux.UpdateSessionAsync(
			await WebResources.GetStringAsync("DynamicCustomProperty.RefreshCommand.HostName"),
			session.SessionID,
			session.Name,
			session.IsPublic,
			session.Code,
			newCustomProperties
		);
	}
	
	static async Task<string> FormatValuesInCommand(Guid sessionID, string command)
	{
		var customProperties = (await SessionManagerPool.Demux.GetSessionAsync(sessionID)).CustomPropertyValues;

		StringBuilder commandVariableDeclarationBlock = new StringBuilder();

		for (int i = 0; i < customProperties.Length; i++)
			commandVariableDeclarationBlock.AppendLine(String.Format("{0} = '{1}'", customPropertyFormatterPrefix + (i + 1), DynamicCustomPropertiesUtil.EscapeSingleQuotes(customProperties[i])));

		command = command.Replace("$Variables", commandVariableDeclarationBlock.ToString());

		return command;
	}

	static string EscapeSingleQuotes(string input)
	{
		return input.Replace("'", "''");
	}
}