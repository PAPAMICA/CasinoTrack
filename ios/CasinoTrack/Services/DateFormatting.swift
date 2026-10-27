import Foundation
import SwiftUI

/// Affichage des dates, fuseau Europe/Paris (CET/CEST). Locale selon langue in-app.
enum CTDates {
    static let tz = TimeZone(identifier: "Europe/Paris")!

    static func locale(for language: AppLanguage) -> Locale { language.locale }

    /// Locale in-app (UserDefaults) — safe hors MainActor (StatsEngine, etc.).
    static var locale: Locale {
        locale(for: storedLanguage)
    }

    static func calendar(for language: AppLanguage = .fr) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = language.locale
        cal.timeZone = tz
        return cal
    }

    static var calendar: Calendar {
        calendar(for: storedLanguage)
    }

    private static var storedLanguage: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.fr.rawValue
        return AppLanguage(rawValue: raw) ?? .fr
    }

    /// Compat: ancienne constante fr_FR (préférence: `locale`).
    static let fr = Locale(identifier: "fr_FR")

    @MainActor
    static func string(
        _ date: Date,
        date dateStyle: Date.FormatStyle.DateStyle = .abbreviated,
        time timeStyle: Date.FormatStyle.TimeStyle = .shortened
    ) -> String {
        var style = Date.FormatStyle(date: dateStyle, time: timeStyle)
        style.locale = locale
        style.timeZone = tz
        return date.formatted(style)
    }
}

/// Durées de session selon langue in-app (ex. « 1 h 23 min » / « 1h 23m »).
enum CTDuration {
    @MainActor
    static func string(_ interval: TimeInterval) -> String {
        string(seconds: Int(interval.rounded()))
    }

    @MainActor
    static func string(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        let en = LanguageStore.shared.language == .en
        if hours > 0 {
            if minutes > 0 {
                return en ? "\(hours)h \(minutes)m" : "\(hours) h \(minutes) min"
            }
            return en ? "\(hours)h" : "\(hours) h"
        }
        if minutes > 0 {
            return en ? "\(minutes)m" : "\(minutes) min"
        }
        return en ? "\(secs)s" : "\(secs) s"
    }
}

/// Affiche la durée d’une session ; se met à jour chaque seconde si la session est ouverte.
struct SessionDurationText: View {
    let session: MachineSession
    var font: Font = .caption

    var body: some View {
        Group {
            if session.isTimingLive {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(CTDuration.string(session.effectiveDuration(at: context.date)))
                }
            } else {
                Text(CTDuration.string(session.effectiveDuration))
            }
        }
        .font(font)
        .monospacedDigit()
    }
}

/// Affiche la durée d’une sortie ; se met à jour chaque seconde si elle est ouverte.
struct VisitDurationText: View {
    let visit: Visit
    var font: Font = .caption

    var body: some View {
        Group {
            if visit.isTimingLive {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(CTDuration.string(visit.effectiveDuration(at: context.date)))
                }
            } else {
                Text(CTDuration.string(visit.effectiveDuration))
            }
        }
        .font(font)
        .monospacedDigit()
    }
}
