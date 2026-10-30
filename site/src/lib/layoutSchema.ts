/** Validation for Room Rig published layout + score JSON used by admin baselines. */

export type FieldError = { field: string; message: string };

const SCORE_KEYS = ["airflow", "lighting", "ergonomics", "spatial"] as const;

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function isFiniteNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

function validateFurnitureItem(item: unknown, index: number, errors: FieldError[]) {
  const prefix = `layout.furniture[${index}]`;
  if (!isRecord(item)) {
    errors.push({ field: prefix, message: "must be an object" });
    return;
  }
  if (typeof item.id !== "string" || !item.id.trim()) {
    errors.push({ field: `${prefix}.id`, message: "required non-empty string" });
  }
  if (typeof item.name !== "string" || !item.name.trim()) {
    errors.push({ field: `${prefix}.name`, message: "required non-empty string" });
  }
  for (const key of ["gridX", "gridY", "width", "height"] as const) {
    if (!isFiniteNumber(item[key])) {
      errors.push({ field: `${prefix}.${key}`, message: "required finite number" });
    }
  }
  if (item.yawDegrees !== undefined && !isFiniteNumber(item.yawDegrees)) {
    errors.push({ field: `${prefix}.yawDegrees`, message: "must be a finite number when set" });
  }
}

/** App layout shape: name/grid + furniture[], or compact room{width,depth}+furniture[]. */
export function validateLayoutJson(value: unknown): FieldError[] {
  const errors: FieldError[] = [];
  if (!isRecord(value)) {
    return [{ field: "layout", message: "must be a JSON object" }];
  }

  const hasRoom = isRecord(value.room);
  const hasGrid = isFiniteNumber(value.gridCols) && isFiniteNumber(value.gridRows);

  if (!hasRoom && !hasGrid) {
    errors.push({
      field: "layout",
      message: "need room:{width,depth} or gridCols+gridRows",
    });
  }

  if (hasRoom) {
    const room = value.room as Record<string, unknown>;
    if (!isFiniteNumber(room.width) || (room.width as number) <= 0) {
      errors.push({ field: "layout.room.width", message: "required positive number" });
    }
    if (!isFiniteNumber(room.depth) || (room.depth as number) <= 0) {
      errors.push({ field: "layout.room.depth", message: "required positive number" });
    }
  }

  if (value.gridCols !== undefined && !isFiniteNumber(value.gridCols)) {
    errors.push({ field: "layout.gridCols", message: "must be a finite number" });
  }
  if (value.gridRows !== undefined && !isFiniteNumber(value.gridRows)) {
    errors.push({ field: "layout.gridRows", message: "must be a finite number" });
  }
  if (value.name !== undefined && typeof value.name !== "string") {
    errors.push({ field: "layout.name", message: "must be a string when set" });
  }
  if (value.presetName !== undefined && typeof value.presetName !== "string") {
    errors.push({ field: "layout.presetName", message: "must be a string when set" });
  }

  if (!Array.isArray(value.furniture)) {
    errors.push({ field: "layout.furniture", message: "required array" });
  } else {
    value.furniture.forEach((item, i) => validateFurnitureItem(item, i, errors));
  }

  return errors;
}

export function validateScoresJson(value: unknown): FieldError[] {
  const errors: FieldError[] = [];
  if (!isRecord(value)) {
    return [{ field: "scores", message: "must be a JSON object" }];
  }
  for (const key of SCORE_KEYS) {
    const n = value[key];
    if (!isFiniteNumber(n)) {
      errors.push({ field: `scores.${key}`, message: "required finite number" });
      continue;
    }
    if (n < 0 || n > 100) {
      errors.push({ field: `scores.${key}`, message: "must be between 0 and 100" });
    }
  }
  return errors;
}

export function parseAndValidateBaselineJson(
  layoutText: string,
  scoresText: string,
): { layout?: unknown; scores?: unknown; errors: FieldError[] } {
  const errors: FieldError[] = [];
  let layout: unknown;
  let scores: unknown;

  try {
    layout = JSON.parse(layoutText);
  } catch {
    errors.push({ field: "layout", message: "invalid JSON" });
  }
  try {
    scores = JSON.parse(scoresText);
  } catch {
    errors.push({ field: "scores", message: "invalid JSON" });
  }

  if (layout !== undefined) errors.push(...validateLayoutJson(layout));
  if (scores !== undefined) errors.push(...validateScoresJson(scores));

  return { layout, scores, errors };
}
