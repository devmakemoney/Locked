//
//  ShieldConfigurationExtension.swift
//  LockedShield
//
//  The screen you hit when a rule is blocking. Slate ground, amber accent —
//  same language as the app icon, so it reads as Créneau and not as some
//  generic system block.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private let slate = UIColor(red: 0.086, green: 0.129, blue: 0.204, alpha: 1.0)
    private let amber = UIColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1.0)

    private func shield(title: String, subject: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: slate.withAlphaComponent(0.96),
            icon: UIImage(systemName: "clock.badge.exclamationmark"),
            title: ShieldConfiguration.Label(text: title, color: .white),
            subtitle: ShieldConfiguration.Label(
                text: subject,
                color: UIColor.white.withAlphaComponent(0.8)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Fermer",
                color: UIColor.black.withAlphaComponent(0.85)
            ),
            primaryButtonBackgroundColor: amber,
            secondaryButtonLabel: nil
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shield(
            title: "Hors créneau",
            subject: "\(application.localizedDisplayName ?? "Cette app") rouvrira à la fin de la plage. La carte est là pour les urgences."
        )
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(shielding: application)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shield(
            title: "Hors créneau",
            subject: "\(webDomain.domain ?? "Ce site") rouvrira à la fin de la plage."
        )
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(shielding: webDomain)
    }
}
