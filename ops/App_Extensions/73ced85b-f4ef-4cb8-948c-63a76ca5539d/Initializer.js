let G = {
	commandBlob: [],
	commandBlobHash: 0,
	commandCount: 0,

	commandsQueuedTimestamp: 0,

	sessionId: null,
	session: null,
	sessionDetails: null,
	sortedEvents: [],

	parentNode: null,
	targetNode: null,
	customInfoNodes: [],
};

function populateCommandBlob() {
	SC.service.GetCommandDefinitions(function (commandDefinitions) {
		try {
			G.commandBlob = JSON.parse(commandDefinitions);
			G.commandBlob.forEach((command) => {
				if (command.type !== 'builtin') {
					command.type = 'remote';
					G.commandCount++;
				}
			});
			updateCommandBlobHash();
		}
		catch (ex) {
			SC.dialog.showModalErrorBox(SC.res['CustomInfo.Alert.CommandDefinitionsParseErrorText'] + '\n' + ex);
			G.commandBlob = [];
			G.commandCount = 0;
		}
	});
}

SC.event.addGlobalHandler(SC.event.PreRender, function (eventArgs) {
	if (SC.context.pageType == "HostPage" || SC.context.pageType == "AdministrationPage")
		populateCommandBlob();
});



SC.event.addGlobalHandler(SC.event.QueryCommandButtons, function (eventArgs) {
	switch (eventArgs.area) {
		case 'ExtrasPopoutPanel':
			if (SC.context.pageType == "HostPage" || SC.context.pageType == "AdministrationPage")
				eventArgs.buttonDefinitions.push({
					commandName: 'EditCustomInfoCommands',
					text: SC.res['CustomInfo.ExtrasPopout.ButtonText'],
				});
			break;
		case 'HostDetailPopoutPanel':
			eventArgs.buttonDefinitions.push({
				commandName: 'RefreshCustomInfoCommands',
				text: SC.res['CustomInfo.HostPopout.ButtonText'],
			});
			break;
		case 'AddCustomInfoCommand':
			eventArgs.buttonDefinitions.push({ commandName: 'AddCustomInfoCommand', text: SC.res['CustomInfo.EditModal.AddCustomInfoCommandButtonText'] });
			break;
		case 'DeleteCustomInfoCommand':
			eventArgs.buttonDefinitions.push({ commandName: 'DeleteCustomInfoCommand', text: SC.res['CustomInfo.EditModal.DeleteCustomInfoCommandButtonText'] });
			break;
		case 'RaiseCustomInfoCommand':
			eventArgs.buttonDefinitions.push({ commandName: 'RaiseCustomInfoCommand', text: SC.res['CustomInfo.EditModal.RaiseCustomInfoCommandButtonText'] });
			break;
		case 'LowerCustomInfoCommand':
			eventArgs.buttonDefinitions.push({ commandName: 'LowerCustomInfoCommand', text: SC.res['CustomInfo.EditModal.LowerCustomInfoCommandButtonText'] });
			break;
	}
});


SC.event.addGlobalHandler(SC.event.ExecuteCommand, function (eventArgs) {
	switch (eventArgs.commandName) {
		case 'EditCustomInfoCommands':
			showCustomInfoEditModal();
			break;
		case 'RefreshCustomInfoCommands':
			populateCommandBlob();
			trySendCustomInfoCommands(true);
			break;
		case 'AddCustomInfoCommand': {
			let container = $('.ContentPanel .CustomInfoItemContainer');
			container.insertBefore(makeCustomInfoItem(), container.lastChild);
		}
			break;
		case 'DeleteCustomInfoCommand': {
			let targetNode = SC.ui.findAncestor(eventArgs.target, (_) => _.className === 'CustomInfoEntry');
			$('.CustomInfoItemContainer').removeChild(targetNode);
		}
			break;
		case 'RaiseCustomInfoCommand': {
			let targetNode = SC.ui.findAncestor(eventArgs.target, (_) => _.className === 'CustomInfoEntry');
			if (targetNode.previousSibling)
				swapCommandEntryData(targetNode, targetNode.previousSibling);
		}
			break;
		case 'LowerCustomInfoCommand': {
			let targetNode = SC.ui.findAncestor(eventArgs.target, (_) => _.className === 'CustomInfoEntry');
			if (targetNode.nextSibling && targetNode.nextSibling != $('.CustomInfoItemContainer').lastChild)
				swapCommandEntryData(targetNode, targetNode.nextSibling);
		}
			break;
	}
});


SC.event.addGlobalHandler(SC.event.InitializeTab, function (eventArgs) {
	if (!isGeneralTab(eventArgs.tabName))
		return;

	G.sessionId = window.getSessionUrlPart();
	if (G.session && G.session.SessionID !== G.sessionId) {
		G.session = G.sessionDetails = null;
		G.commandsQueuedTimestamp = 0;
		G.sortedEvents = [];
	}

	G.parentNode = eventArgs.container;
	let childNodes = Array.from(G.parentNode.childNodes);
	let standardInfoPosition = extensionContext.settingValues['StandardInfoPosition'].toLowerCase();

	if (Number(SC.context.productVersion.split('.')[0]) >= 7) {
		G.targetNode = null;
		if (standardInfoPosition === 'after')
			G.targetNode = childNodes[1];
		else
			if (standardInfoPosition === 'none') {
				childNodes.forEach((child) => {
					if (child !== childNodes[0])
						G.parentNode.removeChild(child);
				});
			}
		G.parentNode.insertBefore($h2(SC.res['CustomInfo.Tab.HeadingText']), G.targetNode);
		G.parentNode = G.parentNode.insertBefore($dl(), G.targetNode);
		G.targetNode = null;
	}
	else {
		G.parentNode = G.parentNode.getElementsByTagName('DL')[0];
		childNodes = Array.from(G.parentNode.childNodes);
		G.targetNode = G.parentNode.lastChild;
		if (standardInfoPosition === 'after')
			G.targetNode = childNodes[0];
		else
			if (standardInfoPosition === 'none') {
				childNodes.forEach((child) => {
					G.parentNode.removeChild(child);
				});
				G.targetNode = null;
			}
	}

	updateAvailableResultsAndVariables(getLastMatchingAndRecentEnoughResponseEvent(extensionContext.settingValues['CommandResponseExpirationSeconds']));
});


SC.event.addGlobalHandler(SC.event.RefreshTab, function (eventArgs) {
	if (!isGeneralTab(eventArgs.tabName))
		return;

	G.session = eventArgs.session;
	G.sessionDetails = eventArgs.sessionDetails;
	G.sortedEvents = window.getSortedEvents(G.sessionDetails).sort((e1, e2) => e2.time - e1.time);

	let lastQueuedEvent = getLastMatchingRequestEvent();
	if (lastQueuedEvent)
		G.commandsQueuedTimestamp = lastQueuedEvent.time;

	let updateGuestInfoButton = $('.ScreenshotPanel a');
	if (updateGuestInfoButton && !updateGuestInfoButton._guestInfoCmdBound) {
		SC.event.addHandler(updateGuestInfoButton, SC.event.ExecuteCommand, function (eventArgs) {
			switch (eventArgs.commandName) {
				case 'UpdateGuestInfo':
					trySendCustomInfoCommands(true);
					break;
			}
		});
		updateGuestInfoButton._guestInfoCmdBound = true;
	}

	trySendCustomInfoCommands();
	updateAvailableResultsAndVariables(getLastMatchingAndRecentEnoughResponseEvent(extensionContext.settingValues['CommandResponseExpirationSeconds']));
});


function getExtensionId() {
	var match = /\/App_Extensions\/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/i.exec(extensionContext.baseUrl || '');
	if (match)
		return match[1];
	throw 'Unable to resolve extension ID from baseUrl: ' + extensionContext.baseUrl;
}

function isSupportedOperatingSystem(operatingSystemName) {
	if (operatingSystemName.startsWith("Windows") || operatingSystemName.startsWith("Microsoft"))
		return true;
	else
		return false;
}


function getCommandResultHash(eventData) {
	return Number(eventData.split('/')[1]);
}


function currentCommandsAreRecentlyRanOrPresentlyQueued(recentSeconds) {
	let lastMatchingRan = getLastMatchingResponseEvent();
	if (lastMatchingRan) {
		if (recentSeconds) {
			if (lastMatchingRan.time >= Date.now() - recentSeconds * 1000) {
				return true;
			}
			else {
				let lastMatchingQueued = getLastMatchingRequestEvent();
				if (lastMatchingQueued)
					if (lastMatchingQueued.time > lastMatchingRan.time) {
						return true;
					}
					else {
						return false;
					}
				else {
					return false;
				}
			}
		}
		else {
			return true;
		}
	}
	else {
		let lastMatchingQueued = getLastMatchingRequestEvent();
		if (lastMatchingQueued) {
			return isLastMatchingRequestEventLast();
		}
	}
}


function trySendCustomInfoCommands(forceIt) {
	if (isSupportedOperatingSystem(G.session.GuestOperatingSystemName) &&
		G.commandCount !== 0 &&
		(forceIt || !currentCommandsAreRecentlyRanOrPresentlyQueued(extensionContext.settingValues['CommandResponseExpirationSeconds']))) {
		if (window.getSessionUrlPart()) {
			window.addEventToSessions(
				[window.getSessionGroupUrlPart()[0]],
				window.getSessionTypeUrlPart(),
				[window.getSessionUrlPart()],
				SC.types.SessionEventType.QueuedCommand,
				null,
				getInputCommand(),
				false,
				false,
				true
			);
		}
	}
}


function stringHash(string) {
	let hash = 5381,
		ii = string.length;

	while (ii)
		hash = (hash * 33) ^ string.charCodeAt(--ii);

	return hash >>> 0;
}


function updateCommandBlobHash() {
	G.commandBlobHash = stringHash(G.commandBlob.reduce((accumulator, value) => accumulator + value.label + value.command + (value.type === 'builtin' ? 'builtin' : 'remote'), ''));
}


function getInputCommand() {
	var headers = getHeaders();
	headers.CommandType = 'Generic';
	var commandText = '';

	for (let ii = 0; ii < G.commandBlob.length; ii++) {
		commandText +=
			'$label' + (ii + 1) + ' = ' + `echo "${G.commandBlob[ii].label}:"` + '\n' +
			'$command' + (ii + 1) + ' = ' +
			(G.commandBlob[ii].type !== 'builtin' ?
				G.commandBlob[ii].command :
				`echo @'\n__BUILTIN__${G.commandBlob[ii].command}\n'@"`) + '\n';
	}

	commandText += 'write-output ';

	for (let jj = 1; jj <= G.commandBlob.length; jj++)
		commandText += '$label' + jj + ',$command' + jj + ',';

	commandText = commandText.substring(0, commandText.length - 1);

	commandText += " | ConvertTo-Xml -As Stream";

	var emptyLinePrefix = 'echo ""';
	commandText = "$Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size (500, 25)" + "\n" + commandText;

	return "#!" + headers.shaBang + "\n" +
		"#maxlength=100000" + "\n" +
		"#timeout=90000" + "\n" +
		headers.modifier + "CUSTOMINFOREQUEST-RESPONSE/" + G.commandBlobHash + headers.delimiter + "\n" +
		headers.modifier + "CommandType: " + headers.CommandType + headers.delimiter + "\n" +
		headers.modifier + "ContentType: " + headers.ContentType + headers.delimiter + "\n" +
		emptyLinePrefix + "\n" + commandText;
}


function getHeaders() {
	return { Processor: "ps", Interface: "powershell", ContentType: "xml", shaBang: "ps", modifier: "echo \"", delimiter: '\"' };
}


function isGeneralTab(tabName) {
	switch (tabName) {
		case 'General':
			return true;
		default:
			return false;
	}
}


function isInformationRequestContent(eventData) {
	return eventData.includes("CUSTOMINFOREQUEST-RESPONSE/");
}


function getLastMatchingEvent(eventType, matchingFunc) {
	return G.sortedEvents
		.filter(_ =>
			_.eventType === eventType &&
			(matchingFunc ? matchingFunc(_) : true))
	[0];
}


function getLastMatchingRequestEvent() {
	return getLastMatchingEvent(SC.types.SessionEventType.QueuedCommand, _ =>
		isInformationRequestContent(_.data) &&
		_.data.split('\n')[3].split('/')[1].replace('"', '') == G.commandBlobHash);
}


function getLastMatchingResponseEvent() {
	return getLastMatchingEvent(SC.types.SessionEventType.RanCommand, _ =>
		isInformationRequestContent(_.data) &&
		_.data.split('/')[1].split('\n')[0] == G.commandBlobHash);

}


function getLastMatchingAndRecentEnoughResponseEvent(recentSeconds) {
	let lastMatching = getLastMatchingResponseEvent();
	return lastMatching ?
		recentSeconds ?
			(lastMatching.time >= Date.now() - recentSeconds * 1000) ?
				lastMatching :
				null :
			lastMatching :
		lastMatching;
}


function isLastMatchingRequestEventLast() {
	return G.sortedEvents
		.filter(_ =>
			_.eventType === SC.types.SessionEventType.QueuedCommand &&
			isInformationRequestContent(_.data))
		.findIndex(_ =>
			_.data
				.split('\n')[3]
				.split('/')[1]
				.replace('"', '') == G.commandBlobHash)
		== 0;
}


function getEventDataXml(eventData) {
	return parseXml(eventData.substring(eventData.indexOf('<?xml'), eventData.length));
}


function formatSessionDataItem(itemName, itemValue) { //todo
	let formattedValue = '';

	if (itemName.endsWith('Time')) {
		formattedValue = SC.util.formatSecondsDuration(itemValue);
	}
	else {
		formattedValue = itemValue;
	}

	return formattedValue;
}


function getSessionDataItem(itemName) {
	let value;

	if (G.session && Object.keys(G.session).includes(itemName))
		value = G.session[itemName];
	else
		if (G.sessionDetails && G.sessionDetails.Session)
			if (Object.keys(G.sessionDetails).includes(itemName))
				value = G.sessionDetails.Session[itemName];
			else
				value = '(' + SC.res['CustomInfo.Tab.InvalidBuiltinDataItemNameErrorText'] + ': "' + itemName + '"';
		else
			value = '(' + SC.res['CustomInfo.Tab.GuestInfoNotAvailableForDataItemErrorText'] + ')';

	return value; //todo add formatter
}


function renderPowerShellObjectElementOrStatus(objectElement) {
	let result = '';
	let children = objectElement.children;

	if (children.length == 0)
		result = objectElement.innerHTML ?
			objectElement.innerHTML.startsWith('__BUILTIN__') ?
				getSessionDataItem(objectElement.innerHTML.substring('__BUILTIN__'.length)) :
				objectElement.innerHTML :
			'';
	else {
		let writeBlanks = false;

		for (let ii = 0; ii < children.length; ii++) {
			if (children[ii].getAttribute('Type') === 'System.Management.Automation.PSCustomObject') {
				let subchildren = children[ii].children;
				for (let jj = 0; jj < subchildren.length; jj++)
					result += subchildren[jj].getAttribute('Name') + ': ' + subchildren[jj].innerHTML + '<br>';
				result += '<br>';
			}
			else {
				if (!SC.util.isNullOrEmpty(children[ii].innerHTML)) {
					result += children[ii].innerHTML;
					writeBlanks = true;
				}

				if (writeBlanks)
					result += '<br>';
			}
		}
	}

	return result;
}


function updateAvailableResultsAndVariables(responseEvent) {
	let results = [];
	let labelRenderer = null;
	let commandRenderer = null;

	Array.from(G.parentNode.getElementsByClassName('CustomInfo')).forEach((_) => {
		G.parentNode.removeChild(_.previousSibling);
		G.parentNode.removeChild(_)
	});

	if (responseEvent) {
		let xml = getEventDataXml(responseEvent.data);
		if (xml)
			results = xml.getElementsByTagName("Object");

		labelRenderer = (item) => renderPowerShellObjectElementOrStatus(item);
		commandRenderer = labelRenderer;
	}
	else {
		for (let blob of G.commandBlob) {
			results.push(blob.label);
			results.push((blob.type === 'builtin' ? '__BUILTIN__' : '') + blob.command);
		}

		labelRenderer = (label) => label + ':';
		commandRenderer = (result) => result.startsWith('__BUILTIN__') ?
			getSessionDataItem(result.substring('__BUILTIN__'.length)) :
			'(' +
			(G.commandsQueuedTimestamp !== 0 ?
				SC.res['CustomInfo.Tab.CommandsQueuedMessageText'] :
				(G.session && !SC.util.isNullOrEmpty(G.session.GuestOperatingSystemName) ?
					isSupportedOperatingSystem(G.session.GuestOperatingSystemName) ?
						SC.res['CustomInfo.Tab.WaitingForGuestInfoMessageText'] :
						SC.res['CustomInfo.Tab.UnsupportedOSMessageText'] :
					SC.res['CustomInfo.Tab.EventsNotLoadedMessageText']))
			+ ')';
	}


	let labelContent = '';
	let commandContent = '';
	for (let resultIndex = 0; resultIndex < results.length; resultIndex += 2) {
		labelContent = labelRenderer(results[resultIndex]);
		commandContent = commandRenderer(results[resultIndex + 1]);
		G.parentNode.insertBefore(
			$dt('', { innerHTML: labelContent, title: commandContent }),
			G.targetNode);
		G.parentNode.insertBefore(
			$dd('', { innerHTML: commandContent, className: 'CustomInfo' }),
			G.targetNode);
	}
}


function swapCommandEntryData(rowA, rowB) {
	let items = [rowA, rowB].map(function (row) {
		return [
			row.getElementsByClassName('CustomInfoLabelInput')[0],
			row.getElementsByClassName('CustomInfoRemoteCheckbox')[0],
			row.getElementsByClassName('CustomInfoCommandContent')[0],
		];
	});

	let temp = [
		items[0][0].value,
		items[0][1].checked,
		items[0][2].value,
	];

	items[0][0].value = items[1][0].value;
	items[0][1].checked = items[1][1].checked;
	items[0][2].value = items[1][2].value;

	items[1][0].value = temp[0];
	items[1][1].checked = temp[1];
	items[1][2].value = temp[2];
}


function updateCommandBlobFromEditModalContent() {
	let rows = $$('.CustomInfoEntry');
	G.commandCount = 0;
	G.commandBlob = rows
		.filter((row) => row.getElementsByClassName('CustomInfoLabelInput')[0].value && row.getElementsByClassName('CustomInfoCommandContent')[0].value)
		.map((row) => {
			let blob = {
				label: row.getElementsByClassName('CustomInfoLabelInput')[0].value || '',
				command: row.getElementsByClassName('CustomInfoCommandContent')[0].value || '',
				type: row.getElementsByClassName('CustomInfoRemoteCheckbox')[0].checked ? 'remote' : 'builtin',
			};

			if (blob.type === 'remote')
				G.commandCount++;

			return blob;
		});
}


function makeCustomInfoItem(commandObject) {
	if (!commandObject)
		commandObject = { label: '', command: '', type: '', };

	return $div({ className: 'CustomInfoEntry' }, [
		$div({ className: 'CustomInfoGrid' }, [
			$input({ className: 'CustomInfoLabelInput', type: 'text', value: commandObject.label ? commandObject.label : '' }),
			$span({ className: 'GridCenter' }, [
				$input({ className: 'CustomInfoRemoteCheckbox', type: 'checkbox', checked: commandObject.type && commandObject.type === 'builtin' ? false : true }),
				$label(SC.res['CustomInfo.EditModal.RemoteCheckboxLabelText']),
			]),
			$span({ className: 'GridCenter' }, [
				SC.command.queryAndCreateCommandButtons('RaiseCustomInfoCommand'),
			]),
			$span({ className: 'GridCenter' }, [
				SC.command.queryAndCreateCommandButtons('LowerCustomInfoCommand'),
			]),
			$span({ className: 'GridEnd' }, [
				SC.command.queryAndCreateCommandButtons('DeleteCustomInfoCommand'),
			]),
		]),
		$textarea({ className: 'CustomInfoCommandContent', value: commandObject.command ? commandObject.command : '' }),
	]);
}


function showCustomInfoEditModal() {
	SC.dialog.showModalButtonDialog('EditRole', SC.res['CustomInfo.EditModal.TitleText'], SC.res['CustomInfo.EditModal.SaveButtonText'], 'Save',
		function (container) {
			SC.ui.setContents(container, [
				$p({ innerText: SC.res['CustomInfo.EditModal.InstructionText'] }),
				$div({ className: 'CustomInfoItemContainer' },
					G.commandBlob
						.map(function (c) {
							return makeCustomInfoItem(c);
						})
						.concat([
							$div({ className: 'AddEntry' }, [
								SC.command.queryAndCreateCommandButtons('AddCustomInfoCommand')
							]),
						])
				),
			]);
		},
		function (eventArgs) {
			switch (eventArgs.commandName) {
				case 'Save':
					try {
						updateCommandBlobFromEditModalContent();
						let oldHash = G.commandBlobHash;
						updateCommandBlobHash();
						if (G.commandBlobHash !== oldHash && SC.context.pageType == 'HostPage') {
							trySendCustomInfoCommands(true); //todo: should we just let refreshtab take care of this?
							updateAvailableResultsAndVariables();
						}
						SC.service.SaveExtensionSettingValues(getExtensionId(), { 'CommandDefinitions': JSON.stringify(G.commandBlob) },
							function (result) {
								SC.dialog.hideModalDialog();
							},
							function (error) { //todo: move to res
								throw 'Error while saving commands. Changes will only be effective until the next page reload.\n' + error;
							}
						);
					}
					catch (ex) {
						alert('Error while saving commands:\n' + ex);
					}
			}
		},
	);
}


function parseXml(xml) {
	var dom = null;
	if (window.DOMParser) {
		try {
			dom = (new DOMParser()).parseFromString(xml, "text/xml");
		}
		catch (e) { dom = null; }
	}
	else if (window.ActiveXObject) {
		try {
			dom = new ActiveXObject('Microsoft.XMLDOM');
			dom.async = false;
			if (!dom.loadXML(xml))
				window.alert(dom.parseError.reason + dom.parseError.srcText);
		}
		catch (e) { dom = null; }
	}
	else
		alert("cannot parse xml string!");
	return dom;
}