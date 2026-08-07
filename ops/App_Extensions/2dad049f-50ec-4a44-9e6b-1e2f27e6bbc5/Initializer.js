var customPropertyCommands = JSON.parse(extensionContext.settingValues.CustomPropertyCommandListJsonBlob);

SC.event.addGlobalHandler(SC.event.PreRender, function (eventArgs) {
	if (SC.context.pageType == 'AdministrationPage')
		SC.util.includeStyleSheet(extensionContext.baseUrl + 'CustomSessionProperties.css');
});

SC.event.addGlobalHandler(SC.event.ExecuteCommand, function(eventArgs){
	switch (eventArgs.commandName) {
		case 'SaveCustomPropertyCommands':
			SC.service.SaveCustomPropertyCommands(JSON.stringify(eventArgs.commandArgument), function() {
				SC.dialog.showModalActivityAndReload('Save', true);
			});
		break;
		case 'UpdateSessionInfo':
			customPropertyCommands = JSON.parse(extensionContext.settingValues.CustomPropertyCommandListJsonBlob);
			var command = getCommandToRun();
			var selectedSessionIDs = [];

			Array.prototype.forEach.call($('.DetailTableContainer table').rows, function (r) {
				if (SC.ui.isChecked(r))
					selectedSessionIDs.push(r._dataItem.SessionID);
			});
			
			if (selectedSessionIDs.length === 0)
				selectedSessionIDs.push(window.getSessionUrlPart());

			sendCommandToSessions(selectedSessionIDs, command, window.getSessionGroupUrlPart());
			break;
		case 'ShowCommandConfigurationModal':
			SC.dialog.showModalButtonDialog(
				'ConfigureSessionVariableCommandModal',
				SC.res['DynamicCustomProperty.ConfigurationModal.Title'],
				SC.res['DynamicCustomProperty.ConfigurationModal.CloseButtonText'],
				'SaveCustomPropertyCommands',
				function (container) {
					var table = $table({ className: 'ConfigurationTable'});
					
					for (let i = 0; i < 8; i++) {
						SC.ui.addContent(table, [
							$tr($td({ className: 'ConfigurationLabel', innerHTML: SC.res['DynamicCustomProperty.ConfigurationModal.CustomPropertyLabel'] + (i + 1) + ':' }), $td( {className: 'ConfigurationInput'}, $input({ type: 'text', value: customPropertyCommands[i], className: 'CustomPropertyCommand' + i }))),
						]);
					}
					SC.ui.addContent(container, [
						$p({ _textResource: 'DynamicCustomProperty.ConfigurationModal.Instructions', className: 'SessionVariableConfigurationInstructions' }),
						$p({ _htmlResource: 'DynamicCustomProperty.ConfigurationModal.VariableInstructions', className: 'SessionVariableConfigurationInstructions' }),
						table,
					]);
				},
				function (eventArgs) {
					var tmpCustomProperties = [];
					for (let i = 0; i < 8; i++) {
						if ($('.CustomPropertyCommand' + i).value !== '')
							tmpCustomProperties.push($('.CustomPropertyCommand' + i).value);
						else
							tmpCustomProperties.push('');
					}
					eventArgs.commandArgument = tmpCustomProperties;
				}
			);
		break;
	}
});

SC.event.addGlobalHandler(SC.event.QueryCommandButtons, function (eventArgs) {
	switch (eventArgs.area) {
		case 'HostDetailPanel':
		case 'HostDetailPopoutPanel':
			eventArgs.buttonDefinitions.push({
				commandName: 'UpdateSessionInfo',
				text: SC.res["DynamicCustomProperty.CommandText"],
				className: 'AlwaysOverflow'
			});
		break;
		case 'ExtrasPopoutPanel':
			if (SC.context.pageType == 'AdministrationPage')
				eventArgs.buttonDefinitions.push(
					{commandName: 'ShowCommandConfigurationModal', text: SC.res['DynamicCustomProperty.ConfigurationModal.OpenButtonText']}
				);
		break;
	}
});

SC.event.addGlobalHandler(SC.event.QueryCommandButtonState, function(eventArgs){
	switch(eventArgs.commandName) {
		case 'UpdateSessionInfo':
			if (eventArgs.commandContext.sessions.length > 0 && getGuestOperatingSystemName(eventArgs.commandContext.sessions[0].GuestOperatingSystemName) == "Windows" ) {
				eventArgs.isEnabled = true;
				eventArgs.isVisible = true;
			} else {
				eventArgs.isEnabled = false;
				eventArgs.isVisible = false;
			}
		break;
	}
});

var getCommandToRun = function() {
	var commandData = "";
	commandData += "#!ps" + "\n";
	commandData += "#maxlength=500000" + "\n";
	commandData += "#timeout=900000" + "\n";
	commandData += "#CUSTOMPROPERTYCOMMANDS-REQUEST/2" + "\n";
	commandData += "echo \"CUSTOMPROPERTYCOMMANDS-RESPONSE/2\"" + "\n";
	
	commandData += "echo \"\"" + "\n";
	
	commandData += "$Variables" + "\n";

	for (var i = 0; i < 8; i++) {
		if (customPropertyCommands[i] !== '') {
			commandData += "echo StartCustomProperty" + (i) + "\n";
			commandData += customPropertyCommands[i] + "\n";
			commandData += "echo EndCustomProperty" + (i) + "\n";
		}
	}
	
	return commandData;
};

var sendCommandToSessions = function (selectedSessionIDs, command, sessionGroupPath) {
	SC.service.AddRefreshCustomPropertiesCommand(
		sessionGroupPath,
		selectedSessionIDs,
		command
	);
};

function getGuestOperatingSystemName(operatingSystemName) {
	var osType = operatingSystemName.indexOf("Windows") >= 0 || operatingSystemName.indexOf("Server") >= 0 ? "Windows"
		: operatingSystemName.indexOf("Linux") >= 0 ? "Linux"
			: operatingSystemName.indexOf("Mac") >= 0 ? "OSX"
				: "Unknown";
	return osType;
}
/*
this stuff for v2 in including other operating systems


function getCommandInfo(osType, commandProcessor) {
	switch (osType) {
		case 'Windows':
			
		break;
		case 'Linux':
			
		break;
		case 'OSX':
			
		break;
	}
}
*/
