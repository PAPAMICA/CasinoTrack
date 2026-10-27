import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(LanguageStore.self) private var language
    @State private var tab = 0

    private var t: L10n { language.t }

    var body: some View {
        TabView(selection: $tab) {
            FloorView()
                .tabItem { Label(t.tabFloor, systemImage: "flame.fill") }
                .tag(0)
            HistoryView()
                .tabItem { Label(t.tabVisits, systemImage: "list.bullet") }
                .tag(1)
            CatalogView()
                .tabItem { Label(t.tabCatalog, systemImage: "square.grid.2x2") }
                .tag(2)
            StatsView()
                .tabItem { Label(t.tabStats, systemImage: "chart.line.uptrend.xyaxis") }
                .tag(3)
        }
        .tint(CTTheme.gold)
        .animation(CTMotion.tabSwitch, value: tab)
    }
}
