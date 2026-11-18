/// Typed, zero-cost views over the JSON returned by the HeatGuard API.
typedef J = Map<String, dynamic>;

List<J> jList(dynamic v) => v is List ? v.map((e) => (e as Map).cast<String, dynamic>()).toList() : <J>[];
J jMap(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
double? jNum(dynamic v) => v is num ? v.toDouble() : null;

extension type Worksite(J j) {
  String get id => j['worksite_id'];
  String get name => j['name'] ?? '';
  String get location => j['location'] ?? '';
  String get environment => j['environment'] ?? 'outdoor';
  List<String> get zones => (j['zones'] as List? ?? []).cast<String>();
  J get status => jMap(j['status']);
  String get sensorStatus => status['sensor_status'] ?? 'offline';
  Reading? get latestReading => j['latest_reading'] == null ? null : Reading(jMap(j['latest_reading']));
  double? get rollingMean => jNum(j['rolling_mean_wbgt']);
}

extension type Crew(J j) {
  String get id => j['crew_id'];
  String get name => j['name'] ?? '';
  String get worksiteId => j['worksite_id'];
  String get zone => j['zone'] ?? '';
  int get workerCount => (j['worker_count'] as num?)?.toInt() ?? 0;
  String get workload => j['workload'] ?? 'unknown';
  String get clothing => j['clothing'] ?? 'unknown';
  String get acclimatization => j['acclimatization'] ?? 'unknown';
  String get regime => j['work_rest_regime'] ?? 'continuous';
  String get shiftStart => j['shift_start'] ?? '07:00';
  double get shiftHours => jNum(j['shift_duration_hours']) ?? 8;
  String get task => j['current_task'] ?? '';
}

extension type Reading(J j) {
  String get id => j['reading_id'];
  String get timestamp => j['timestamp'];
  String? get receivedAt => j['received_at'];
  String? get simClock => j['sim_clock'];
  String? get simDate => j['sim_date'];
  int? get simMinute => (j['sim_minute'] as num?)?.toInt();
  double? get tdb => jNum(j['dry_bulb']);
  double? get tnwb => jNum(j['natural_wet_bulb']);
  double? get tg => jNum(j['globe_temperature']);
  double? get rh => jNum(j['relative_humidity']);
  double? get wbgt => jNum(j['wbgt']);
  String? get formula => j['wbgt_formula'];
  bool? get directSolar => j['direct_solar'] as bool?;
  bool get lateSync => j['late_sync'] == true;
  List<String> get overrides => (j['manual_override'] as List? ?? []).cast<String>();
  String get origin => j['data_origin'] ?? 'SIMULATED';
  String get validity => jMap(j['validation'])['measurement_validity'] ?? 'invalid';
  List<J> get issues => jList(jMap(j['validation'])['issues']);
  J get sensorStatus => jMap(j['sensor_status']);
}

extension type Assessment(J j) {
  String get id => j['assessment_id'];
  String get crewId => j['crew_id'];
  String get crewName => j['crew_name'] ?? '';
  String get worksiteId => j['worksite_id'];
  String get timestamp => j['timestamp'];
  String? get simClock => j['sim_clock'];
  String get status => j['assessment_status'];
  String get category => j['risk_category'];
  int get level => (j['risk_level'] as num).toInt();
  double? get wbgt => jNum(j['wbgt']);
  double? get effectiveWbgt => jNum(j['effective_wbgt']);
  String get explanation => j['explanation'] ?? '';
  List<J> get factors => jList(j['contributing_factors']);
  List<J> get actions => jList(j['recommended_actions']);
  J get dataQuality => jMap(j['data_quality']);
  double get completeness => jNum(j['data_completeness']) ?? 0;
  J get inputs => jMap(j['inputs_used']);
  J? get limit => j['limit_details'] == null ? null : jMap(j['limit_details']);
  String get method => j['assessment_method'] ?? '';
  String get reference => j['guideline_reference'] ?? '';
  List<String> get limitations => (j['limitations'] as List? ?? []).cast<String>();
  String get origin => j['data_origin'] ?? 'SIMULATED';
  List<J> get regulatoryFlags => jList(j['regulatory_flags']);
  bool get middayBreak => regulatoryFlags.isNotEmpty;
  Crew? get crew => j['crew'] == null ? null : Crew(jMap(j['crew']));
}

extension type Alert(J j) {
  String get id => j['alert_id'];
  String get timestamp => j['timestamp'];
  String get updatedAt => j['updated_at'];
  String get worksiteId => j['worksite_id'];
  String get worksiteName => j['worksite_name'] ?? '';
  String get crewId => j['crew_id'];
  String get crewName => j['crew_name'] ?? '';
  String get type => j['alert_type'];
  String get severity => j['severity'];
  String get peakSeverity => j['peak_severity'];
  int get severityLevel => (j['severity_level'] as num).toInt();
  String get explanation => j['explanation'] ?? '';
  List<J> get factors => jList(j['contributing_factors']);
  List<J> get recommendations => jList(j['recommendations']);
  bool get acknowledged => j['acknowledgement_status'] == 'acknowledged';
  String? get acknowledgedAt => j['acknowledged_at'];
  String? get acknowledgedBy => j['acknowledged_by'];
  String get resolution => j['resolution_status'];
  bool get resolved => resolution == 'resolved';
  String? get resolvedAt => j['resolved_at'];
  String? get resolutionNote => j['resolution_note'];
  int get escalation => (j['escalation_level'] as num?)?.toInt() ?? 0;
  int get duplicates => (j['duplicate_count'] as num?)?.toInt() ?? 0;
  int get improvingStreak => (j['improving_streak'] as num?)?.toInt() ?? 0;
  String? get latestCategory => j['latest_category'];
  List<String> get interventionIds => (j['intervention_ids'] as List? ?? []).cast<String>();
  List<J> get history => jList(j['history']);
}

extension type Intervention(J j) {
  String get id => j['intervention_id'];
  String? get alertId => j['alert_id'];
  String get crewId => j['crew_id'];
  String get crewName => j['crew_name'] ?? '';
  String get action => j['action'];
  String get actionLabel => j['action_label'] ?? '';
  String get status => j['status'];
  bool get active => status == 'active';
  String get start => j['start_time'];
  String? get end => j['end_time'];
  int? get plannedMinutes => (j['planned_duration_minutes'] as num?)?.toInt();
  String get supervisor => j['supervisor_id'] ?? '';
  String get notes => j['notes'] ?? '';
  String get completionNotes => j['completion_notes'] ?? '';
  J get contextChanges => jMap(j['context_changes']);
  J? get baseline => j['baseline_assessment'] == null ? null : jMap(j['baseline_assessment']);
  List<J> get followUps => jList(j['follow_up_assessments']);
  String? get outcome => j['outcome'];
}
