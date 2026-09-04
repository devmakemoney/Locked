import Foundation

// Harnais de test pour la logique pure de ScheduleRule (compilee a part).

var failures = 0
var checks = 0

func check(_ condition: Bool, _ label: String) {
    checks += 1
    if !condition {
        failures += 1
        print("  ECHEC  \(label)")
    }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/Paris")!

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

// 2026-09-07 est un lundi.
let lundi = 2, mardi = 3, samedi = 7, dimanche = 1

// --- Regle simple, sans passage de minuit : travail matinee lun-ven 10h00-13h15
let matinee = TimeWindow(
    weekdays: [2, 3, 4, 5, 6], startMinutes: 600, endMinutes: 795)

print("Regle simple 10h00-13h15 lun-ven")
check(!matinee.isActive(at: date(2026, 9, 7, 9, 59), calendar: cal), "9h59 lundi : inactif")
check(matinee.isActive(at: date(2026, 9, 7, 10, 0), calendar: cal), "10h00 lundi : actif")
check(matinee.isActive(at: date(2026, 9, 7, 13, 14), calendar: cal), "13h14 lundi : actif")
check(!matinee.isActive(at: date(2026, 9, 7, 13, 15), calendar: cal), "13h15 lundi : inactif (borne exclue)")
check(!matinee.isActive(at: date(2026, 9, 12, 11, 0), calendar: cal), "11h00 samedi : inactif")
check(!matinee.crossesMidnight, "ne traverse pas minuit")
check(matinee.durationMinutes == 195, "duree 3h15")

// --- Regle traversant minuit : loisir bloque 20h00 -> 18h40, tous les jours
let loisir = TimeWindow(
    weekdays: [1, 2, 3, 4, 5, 6, 7], startMinutes: 1200, endMinutes: 1120)

print("Regle traversant minuit 20h00-18h40 tous les jours")
check(loisir.crossesMidnight, "traverse minuit")
check(loisir.durationMinutes == 1360, "duree 22h40")
check(loisir.isActive(at: date(2026, 9, 7, 20, 0), calendar: cal), "20h00 : actif")
check(loisir.isActive(at: date(2026, 9, 7, 23, 59), calendar: cal), "23h59 : actif")
check(loisir.isActive(at: date(2026, 9, 8, 0, 30), calendar: cal), "00h30 lendemain : actif")
check(loisir.isActive(at: date(2026, 9, 8, 18, 39), calendar: cal), "18h39 : actif")
check(!loisir.isActive(at: date(2026, 9, 8, 18, 40), calendar: cal), "18h40 : inactif, la fenetre s'ouvre")
check(!loisir.isActive(at: date(2026, 9, 8, 19, 30), calendar: cal), "19h30 : inactif")

// --- Traversee de minuit avec jours restreints : le lendemain herite du jour precedent
let nuitSemaine = TimeWindow(
    weekdays: [6], startMinutes: 1065, endMinutes: 480) // vendredi 17h45 -> 08h00

print("Regle vendredi 17h45 -> samedi 08h00")
check(nuitSemaine.isActive(at: date(2026, 9, 11, 18, 0), calendar: cal), "vendredi 18h : actif")
check(nuitSemaine.isActive(at: date(2026, 9, 12, 7, 59), calendar: cal), "samedi 7h59 : actif (queue du vendredi)")
check(!nuitSemaine.isActive(at: date(2026, 9, 12, 8, 0), calendar: cal), "samedi 8h00 : inactif")
check(!nuitSemaine.isActive(at: date(2026, 9, 12, 18, 0), calendar: cal), "samedi 18h : inactif (samedi non coche)")
check(!nuitSemaine.isActive(at: date(2026, 9, 11, 7, 0), calendar: cal), "vendredi 7h : inactif (queue du jeudi, non coche)")

// --- Bascule dimanche -> lundi (weekday 1 -> 2), le cas qui casse les index
let dimancheSoir = TimeWindow(
    weekdays: [1], startMinutes: 1320, endMinutes: 360) // dim 22h -> lun 06h

print("Bascule dimanche -> lundi")
check(dimancheSoir.isActive(at: date(2026, 9, 6, 23, 0), calendar: cal), "dimanche 23h : actif")
check(dimancheSoir.isActive(at: date(2026, 9, 7, 5, 0), calendar: cal), "lundi 5h : actif (queue du dimanche)")
check(!dimancheSoir.isActive(at: date(2026, 9, 7, 6, 0), calendar: cal), "lundi 6h : inactif")

// --- Groupe desactive
var groupeOff = BlockGroup(name: "Off", windows: [matinee], isEnabled: false)
check(!groupeOff.isActive(at: date(2026, 9, 7, 11, 0), calendar: cal), "groupe desactive : jamais actif")
groupeOff.isEnabled = true
check(groupeOff.isActive(at: date(2026, 9, 7, 11, 0), calendar: cal), "groupe reactive : actif")

// --- Segments
print("Segments")
let idMatinee = UUID()
let segsSimple = matinee.segments(groupID: idMatinee, from: date(2026, 9, 7, 0, 0), days: 3, calendar: cal)
check(segsSimple.count == 3, "3 jours ouvres sur 3 jours a partir du lundi (eu \(segsSimple.count))")
check(segsSimple.allSatisfy { $0.end > $0.start }, "toutes les fenetres ont une fin apres le debut")

let segsMinuit = loisir.segments(groupID: UUID(), from: date(2026, 9, 7, 0, 0), days: 2, calendar: cal)
check(segsMinuit.count == 4, "2 segments par jour quand ca traverse minuit (eu \(segsMinuit.count))")
check(segsMinuit.allSatisfy { $0.end > $0.start }, "segments coherents")
let noms = Set(segsMinuit.map(\.activityName))
check(noms.count == segsMinuit.count, "noms d'activite uniques")

// Les fenetres deja terminees sont ecartees.
let segsTard = matinee.segments(groupID: idMatinee, from: date(2026, 9, 7, 14, 0), days: 1, calendar: cal)
check(segsTard.isEmpty, "aucune fenetre le lundi apres 14h (eu \(segsTard.count))")

// Coherence croisee : chaque segment doit contenir des instants ou isActive est vrai.
print("Coherence segments <-> isActive")
for seg in segsMinuit.prefix(4) {
    let milieu = seg.start.addingTimeInterval(seg.end.timeIntervalSince(seg.start) / 2)
    check(loisir.isActive(at: milieu, calendar: cal),
          "milieu du segment \(seg.start) actif")
}
for seg in segsSimple {
    let milieu = seg.start.addingTimeInterval(seg.end.timeIntervalSince(seg.start) / 2)
    check(matinee.isActive(at: milieu, calendar: cal), "milieu du segment matinee actif")
}

// --- Libelles
check(TimeWindow.timeLabel(1065) == "17h45", "libelle 17h45")
check(TimeWindow.timeLabel(0) == "00h00", "libelle minuit")
check(matinee.weekdaysLabel == "Lun – Ven", "libelle lun-ven (eu \(matinee.weekdaysLabel))")
check(loisir.weekdaysLabel == "Tous les jours", "libelle tous les jours")

// --- Groupe a plusieurs plages : le cas qui a motive la refonte
// Loisir : 00h-08h, 10h-14h, 17h-00h, tous les jours.
let multi = BlockGroup(name: "Loisir", windows: [
    TimeWindow(weekdays: [1,2,3,4,5,6,7], startMinutes: 0,    endMinutes: 480),
    TimeWindow(weekdays: [1,2,3,4,5,6,7], startMinutes: 600,  endMinutes: 840),
    TimeWindow(weekdays: [1,2,3,4,5,6,7], startMinutes: 1020, endMinutes: 1440),
])
print("Groupe a 3 plages 00h-08h / 10h-14h / 17h-00h")
check(multi.isActive(at: date(2026, 9, 7, 3, 0), calendar: cal), "03h : actif (plage 1)")
check(!multi.isActive(at: date(2026, 9, 7, 9, 0), calendar: cal), "09h : inactif (trou)")
check(multi.isActive(at: date(2026, 9, 7, 11, 0), calendar: cal), "11h : actif (plage 2)")
check(!multi.isActive(at: date(2026, 9, 7, 15, 0), calendar: cal), "15h : inactif (trou)")
check(multi.isActive(at: date(2026, 9, 7, 22, 0), calendar: cal), "22h : actif (plage 3)")
check(!multi.isActive(at: date(2026, 9, 7, 8, 0), calendar: cal), "08h00 pile : inactif, la plage 1 s'arrete")
check(multi.windows.count == 3, "3 plages conservees")
check(multi.weeklyMinutes == (480 + 240 + 420) * 7, "minutes hebdo cumulees (eu \(multi.weeklyMinutes))")

let segsMulti = multi.segments(from: date(2026, 9, 7, 0, 0), days: 2, calendar: cal)
check(segsMulti.count == 6, "3 plages x 2 jours = 6 segments (eu \(segsMulti.count))")
check(Set(segsMulti.map(\.activityName)).count == 6, "noms d'activite uniques entre plages du meme groupe")
check(segsMulti.allSatisfy { $0.groupID == multi.id }, "tous les segments portent l'id du groupe")

// Un groupe vide ne bloque rien.
let vide = BlockGroup(name: "Vide", windows: [])
check(!vide.isActive(at: date(2026, 9, 7, 12, 0), calendar: cal), "groupe sans plage : inactif")
check(vide.segments(from: date(2026, 9, 7, 0, 0), days: 3, calendar: cal).isEmpty, "groupe sans plage : aucun segment")

print("")
print("\(checks - failures)/\(checks) verifications passees")
exit(failures == 0 ? 0 : 1)
