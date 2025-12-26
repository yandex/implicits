// Copyright 2025 Yandex LLC. All rights reserved.

import Implicits
@_spi(Implicits) import ShowcaseDependency

public typealias Planet = String

public final class DeathStar {
  public init() {}

  // FIXME: Make it public, fix codegen
  internal func destroy(_ planet: Planet, _ scope: ImplicitScope) {
    @Implicit(\.authority)
    var authority: Bool
    guard authority else {
      print("Unable to destroy \(planet)! Not enough authority.")
      return
    }

    @Implicit(\.laserPower)
    var laserPower: Int

    @Implicit(\.target)
    var target: String

    let laserStatus = laser(scope)
    let shieldStatus = shield(scope)
    let tractorStatus = tractorBeam(scope)

    print(
      "👽 Firing Death Star laser at \(planet) with power \(laserPower)! Target: \(target). Status: \(laserStatus) BOOM! 💥"
    )
    print("🛡️ Shield report: \(shieldStatus)")
    print("🧲 Tractor beam: \(tractorStatus)")
  }

  internal func destroyAsync(_ planet: Planet) async {
    await withScope { scope in
      @Implicit(\.authority)
      var authority = true

      @Implicit(\.laserPower)
      var laserPower = 9000

      @Implicit(\.target)
      var target = planet

      @Implicit(\.shieldLevel)
      var shieldLevel = 100

      @Implicit(\.beamStrength)
      var beamStrength = 50

      await prepareWeapons(scope)
      await chargeMainReactor()
      destroy(planet, scope)
    }
  }

  private func prepareWeapons(_ scope: ImplicitScope) async {
    @Implicit(\.laserPower)
    var laserPower: Int
    print("⚡ Charging weapons to power level \(laserPower)...")

    // Simulate async weapon calibration
    try? await Task.sleep(nanoseconds: 1_000_000)

    await calibrateTargeting(scope)
    print("🎯 Weapons calibrated to power level \(laserPower + 1000)")
  }

  private func calibrateTargeting(_: ImplicitScope) async {
    @Implicit(\.target)
    var target: String
    // Simulate async targeting calibration
    try? await Task.sleep(nanoseconds: 500_000)
    print("🔭 Targeting system locked on \(target)")
  }

  private func chargeMainReactor() async {
    // Simulate async reactor charging
    try? await Task.sleep(nanoseconds: 1_000_000)
    print("🔋 Main reactor fully charged")
  }
}

extension ImplicitsKeys {
  public static let authority = Key<Bool>()
}
