using System.Threading.Tasks;
using System.Web;

namespace ScreenConnect;

public class ContextProvider : IClientScriptCustomContextProvider
{
	public async Task<object> GetScriptCustomContextAsync(HttpContext context) =>
		new
		{
			ShowUsersTab = await LicensingInfo.HasCapabilitiesAsync(BasicLicenseCapabilities.AccessManagement),
			CanSendCommands = await LicensingInfo.HasCapabilitiesAsync(BasicLicenseCapabilities.LoadRmmExtension) || await LicensingInfo.HasCapabilitiesAsync(BasicLicenseCapabilities.LoadPremiumExtension),
		};
}
