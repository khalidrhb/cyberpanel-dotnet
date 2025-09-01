try:
    from django.urls import path
except ImportError:
    from django.conf.urls import url as path

from . import views

urlpatterns = [
    path('', views.index, name='cyberpanel_dotnet_plugin_index'),
    path('enable', views.enable_site, name='cyberpanel_dotnet_plugin_enable'),
    path('deploy', views.deploy_site, name='cyberpanel_dotnet_plugin_deploy'),
    path('toggle', views.toggle_mode, name='cyberpanel_dotnet_plugin_toggle'),
    path('restart', views.restart_service, name='cyberpanel_dotnet_plugin_restart'),
    path('signalr/toggle', views.signalr_toggle, name='cyberpanel_dotnet_plugin_signalr_toggle'),
    path('service/status', views.service_status, name='cyberpanel_dotnet_plugin_service_status'),
]
