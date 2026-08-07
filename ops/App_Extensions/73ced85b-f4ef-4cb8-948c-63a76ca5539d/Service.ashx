<%@ WebHandler Language="C#" Class="Service" %>

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using System.Net.Mail;
using System.Net.Configuration;
using System.Web;
using ScreenConnect;
using ScreenConnect.SQLite;

[DemandAnyPermission]
public class Service : WebServiceBase
{
	public string GetCommandDefinitions()
	{
		return ExtensionContext.Current.GetSettingValue("CommandDefinitions");
	}
}
