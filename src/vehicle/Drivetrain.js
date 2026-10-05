/**
 * Engine + automatic gearbox model.
 *
 *  - Torque curve: (rpm, Nm) samples, monotone cubic (Fritsch–Carlson)
 *    interpolation → smooth, no overshoot between samples.
 *  - Engine rpm is locked to the driven wheels through the gear & final drive,
 *    except at launch where a slipping clutch lets the engine rev up.
 *  - Automatic shifting with a torque cut during the shift, rev limiter,
 *    engine braking, and reverse.
 *
 * Output is a total longitudinal force at the contact patches (N), to be
 * split across the driven wheels by the vehicle.
 */
export class Drivetrain {
  constructor({
    torqueCurve = [
      [800, 95],
      [1500, 128],
      [2500, 158],
      [3500, 178],
      [4200, 186],
      [5000, 178],
      [5800, 160],
      [6500, 132],
    ],
    gears = [3.42, 2.05, 1.38, 1.0, 0.8],
    reverseRatio = 3.25,
    finalDrive = 4.1,
    efficiency = 0.88,
    idleRpm = 850,
    redline = 6500,
    shiftUpRpm = 5900,
    shiftDownRpm = 2300,
    shiftTime = 0.24,
    engineBrakeCoeff = 0.022, // Nm per rpm when off-throttle
    wheelRadius = 0.33,
  } = {}) {
    this.curve = torqueCurve;
    this.gears = gears;
    this.reverseRatio = reverseRatio;
    this.finalDrive = finalDrive;
    this.efficiency = efficiency;
    this.idleRpm = idleRpm;
    this.redline = redline;
    this.shiftUpRpm = shiftUpRpm;
    this.shiftDownRpm = shiftDownRpm;
    this.shiftTime = shiftTime;
    this.engineBrakeCoeff = engineBrakeCoeff;
    this.wheelRadius = wheelRadius;

    this.gear = 1; // -1 = reverse, 0 = neutral, 1..n
    this.rpm = idleRpm;
    this.shiftTimer = 0;
    this._tangents = this._computeTangents();
  }

  /** Fritsch–Carlson monotone cubic tangents for the torque curve. */
  _computeTangents() {
    const c = this.curve;
    const n = c.length;
    const d = [];
    for (let i = 0; i < n - 1; i++) d.push((c[i + 1][1] - c[i][1]) / (c[i + 1][0] - c[i][0]));
    const m = new Array(n);
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    for (let i = 0; i < n - 1; i++) {
      if (d[i] === 0) {
        m[i] = m[i + 1] = 0;
        continue;
      }
      const a = m[i] / d[i];
      const b = m[i + 1] / d[i];
      const s = a * a + b * b;
      if (s > 9) {
        const t = 3 / Math.sqrt(s);
        m[i] = t * a * d[i];
        m[i + 1] = t * b * d[i];
      }
    }
    return m;
  }

  /** Peak engine torque available at `rpm` (Nm). */
  torqueAt(rpm) {
    const c = this.curve;
    if (rpm <= c[0][0]) return c[0][1];
    if (rpm >= c[c.length - 1][0]) return c[c.length - 1][1];
    let i = 0;
    while (rpm > c[i + 1][0]) i++;
    const [x0, y0] = c[i];
    const [x1, y1] = c[i + 1];
    const h = x1 - x0;
    const t = (rpm - x0) / h;
    const t2 = t * t;
    const t3 = t2 * t;
    const m = this._tangents;
    return (
      (2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * h * m[i + 1]
    );
  }

  get ratio() {
    if (this.gear === 0) return 0;
    return this.gear < 0 ? -this.reverseRatio : this.gears[this.gear - 1];
  }

  get gearLabel() {
    return this.gear < 0 ? 'R' : this.gear === 0 ? 'N' : String(this.gear);
  }

  /**
   * @param {number} dt
   * @param {number} speed signed forward speed (m/s)
   * @param {number} throttle 0..1
   * @returns {number} total drive force at the wheels (N), signed along +forward
   */
  update(dt, speed, throttle) {
    const ratio = this.ratio;
    const total = Math.abs(ratio) * this.finalDrive;
    const wheelRpm = (Math.abs(speed) / this.wheelRadius) * (60 / (2 * Math.PI));
    const lockedRpm = wheelRpm * total;

    // Clutch slip at launch: the engine can rev above the wheel-locked rpm.
    const launchRpm = this.idleRpm + throttle * 2600;
    const target = Math.max(
      lockedRpm,
      this.idleRpm,
      lockedRpm < launchRpm ? launchRpm * Math.min(1, throttle * 1.5) : 0,
    );
    this.rpm += (target - this.rpm) * Math.min(1, dt * 10);
    this.rpm = Math.min(this.rpm, this.redline + 150);

    // Automatic gearbox (forward gears only).
    if (this.shiftTimer > 0) this.shiftTimer -= dt;
    else if (this.gear > 0) {
      if (lockedRpm > this.shiftUpRpm && this.gear < this.gears.length) this._shift(this.gear + 1);
      else if (lockedRpm < this.shiftDownRpm && this.gear > 1) this._shift(this.gear - 1);
    }

    if (ratio === 0) return 0;
    const shifting = this.shiftTimer > 0;
    const limiter = this.rpm >= this.redline ? 0 : 1;
    let torque = shifting ? 0 : this.torqueAt(this.rpm) * throttle * limiter;
    // Engine braking when off-throttle (opposes motion).
    if (throttle < 0.05 && !shifting)
      torque -= this.engineBrakeCoeff * this.rpm * Math.sign(speed * Math.sign(ratio) || 0);
    return (torque * ratio * this.finalDrive * this.efficiency) / this.wheelRadius;
  }

  _shift(gear) {
    this.gear = gear;
    this.shiftTimer = this.shiftTime;
  }

  setReverse(on) {
    if (on && this.gear !== -1) this._shift(-1);
    else if (!on && this.gear === -1) this._shift(1);
  }
}
