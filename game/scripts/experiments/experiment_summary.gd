extends RefCounted

static func summarize(rows: Array) -> String:
	var groups := {}
	for row in rows:
		var key: String = row.scenario_id + "  /  " + row.provider
		if row.common_executor: key += "  /  공통 명령"
		if not groups.has(key): groups[key] = []
		groups[key].append(row)
	var lines := PackedStringArray()
	for key in groups:
		var items: Array = groups[key]
		var times := []
		var total_time := 0.0
		var appropriate := 0
		var timely := 0
		var scores := []
		var counts := {}
		var completed := {}
		var started := {}
		var outcomes := {}
		var duration := 0.0
		for row in items:
			counts[row.status] = counts.get(row.status,0) + 1
			if row.elapsed_ms != null:
				times.append(float(row.elapsed_ms))
				total_time += float(row.elapsed_ms)
			if row.appropriate == true: appropriate += 1
			if row.timely_valid == true: timely += 1
			if row.accepted and not row.common_executor and row.rating is Dictionary:
				scores.append(float(row.rating.total))
			if row.combat is Dictionary:
				var c: Dictionary = row.combat
				outcomes[c.outcome] = outcomes.get(c.outcome,0) + 1
				duration += c.duration_seconds
				for event in c.events:
					if event.event == "support_started": started[event.action] = started.get(event.action,0) + 1
					if event.event == "support_completed": completed[event.action] = completed.get(event.action,0) + 1
		var parts := PackedStringArray(["%s   ·   %d건" % [key,items.size()],JSON.stringify(counts)])
		if not times.is_empty():
			times.sort()
			var n := times.size()
			var median := (float(times[(n-1)/2]) + float(times[n/2])) / 2
			parts.append("평균 %.1f / 중앙 %.1f ms (%d건)" % [total_time/n,median,n])
		if items[0].kind == "decision":
			parts.append("적절 %.1f%% · 시간 내 유효 %.1f%%" % [100.0*appropriate/items.size(),100.0*timely/items.size()])
		if not scores.is_empty():
			parts.append("수동 평가 %.2f / 8 (%d건)" % [scores.reduce(func(a,b): return a+b,0.0)/scores.size(),scores.size()])
		if not outcomes.is_empty():
			parts.append("종료 %s · 평균 %.2f초 · 지원 시작 %s / 완료 %s" % [JSON.stringify(outcomes),duration/items.size(),JSON.stringify(started),JSON.stringify(completed)])
		lines.append("    ".join(parts))
	return "\n".join(lines)
