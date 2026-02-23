import SwiftUI

/// The root view of Liquid Transit Roma.
///
/// Uses the native iOS 26 TabView with Liquid Glass styling.
/// Three tabs: Preferiti, Linee, Fermate. A floating search button
/// opens SearchView as a sheet.
struct ContentView: View {

    @State private var showSearch = false

    var body: some View {
        TabView {
            Tab("Preferiti", systemImage: "heart.fill") {
                HomeView()
            }

            Tab("Linee", systemImage: "bus.fill") {
                NavigationStack {
                    LinesView()
                }
            }

            Tab("Fermate", systemImage: "mappin.and.ellipse") {
                StopsView()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(width: 52, height: 52)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(.trailing, 16)
            .padding(.bottom, 72)
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
