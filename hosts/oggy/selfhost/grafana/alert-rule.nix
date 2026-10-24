{
  uid,
  title,
  expr,
  condition,
  duration,
  description,
  summary,
  dashboard ? "node-exporter-full",
  panelId,
  severity ? "warning",
  labels ? {
    inherit severity;
    scope = "infrastructure";
  },
  timeRange ? 300,
}:
{
  inherit uid title;
  condition = "B";
  for = duration;
  noDataState = "OK";
  execErrState = "Error";
  annotations = {
    inherit description summary;
    __dashboardUid__ = dashboard;
    __panelId__ = toString panelId;
  };
  notification_settings = {
    receiver = "qingping-telegram";
    group_wait = "30s";
    group_interval = "5m";
    repeat_interval = "4h";
  };
  data = [
    {
      refId = "A";
      datasourceUid = "PBFA97CFB590B2093";
      relativeTimeRange = {
        from = timeRange;
        to = 0;
      };
      model = {
        refId = "A";
        inherit expr;
        instant = true;
        range = false;
      };
    }
    {
      refId = "B";
      datasourceUid = "__expr__";
      relativeTimeRange = {
        from = 0;
        to = 0;
      };
      model = {
        refId = "B";
        type = "math";
        expression = condition;
      };
    }
  ];
}
// (if labels == null then { } else { inherit labels; })
