from django.apps import AppConfig

class CyberpanelDotnetPluginConfig(AppConfig):
    name = 'cyberpanel_dotnet_plugin'
    verbose_name = 'CyberPanel .NET Manager'

    def ready(self):
        try:
            import cyberpanel_dotnet_plugin.signals  # optional
        except Exception:
            pass
