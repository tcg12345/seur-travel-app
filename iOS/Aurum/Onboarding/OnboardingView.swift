import SwiftUI
import UserNotifications

struct AppEntryView: View {
    @Environment(OnboardingStore.self) private var onboarding
    private var bypass: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && !args.contains("--onboarding-testing")
    }
    var body: some View {
        if onboarding.profile.completed || bypass { RootView() }
        else { OnboardingView() }
    }
}

struct OnboardingView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(TravelStore.self) private var travel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var review = false
    @State private var step = 0
    @State private var signingIn = false
    @State private var accountReturnStep = 3
    @AccessibilityFocusState private var titleFocused: Bool
    private let symbols = ["bed.double", "fork.knife", "building.columns", "leaf"]
    private let descriptions = ["Hotels that become part of the story.", "The tables worth planning a trip around.", "Beautiful places. A fresh perspective.", "Slower mornings and room to unwind."]
    var body: some View {
        Group {
            if step == 0 { welcome.preferredColorScheme(.dark) }
            else if step == 4 {
                OnboardingAccountView(signingIn: signingIn, onBack: { move(to: accountReturnStep) }, onContinue: { move(to: 5) })
            } else if step == 5 {
                MembershipPreviewView(onBack: { move(to: 4) }, onFinish: { move(to: 6) })
            } else if step == 6 {
                OnboardingNotificationsView(onBack: { move(to: 5) }, onContinue: finish)
            } else { preferences }
        }
        .background(Color.canvas)
        .onAppear { step = review ? 1 : onboarding.profile.step }
        .sensoryFeedback(.selection, trigger: step)
    }
    private var welcome: some View {
        GeometryReader { geo in
            ZStack {
                GeometryReader { imageGeometry in
                    Image("bangkok").resizable().scaledToFill().frame(width: imageGeometry.size.width, height: imageGeometry.size.height).clipped().accessibilityHidden(true)
                }.ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.35), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        SeurLogo(size: 38)
                        Text("SEUR").font(.system(size: 15, weight: .medium)).tracking(6)
                        Spacer()
                        Text("TRAVEL, CONSIDERED").font(.system(size: 8, weight: .semibold)).tracking(1.5)
                    }.padding(.top, 20)
                    Spacer(minLength: 24)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Label("EXCEPTIONAL STAYS. REMARKABLE TABLES.", systemImage: "sparkle")
                                .font(.system(size: 9, weight: .semibold)).tracking(1.2).padding(.horizontal, 13).padding(.vertical, 11)
                                .glassEffect(.clear, in: .capsule)
                            Editorial("Go for the place.\nStay for the feeling.", size: 43).dynamicTypeSize(...DynamicTypeSize.accessibility1).accessibilityIdentifier("onboarding-welcome")
                            Text("Discover extraordinary hotels, find your next great table, and bring the whole journey together.")
                                .font(.body).foregroundStyle(.white.opacity(0.85)).lineSpacing(4)
                            HStack(spacing: 22) {
                                welcomeFeature("Stays", "bed.double")
                                welcomeFeature("Dining", "fork.knife")
                                welcomeFeature("Journeys", "point.topleft.down.to.point.bottomright.curvepath")
                            }.padding(.top, 6)
                        }.padding(.bottom, 24)
                    }.scrollIndicators(.hidden).defaultScrollAnchor(.bottom, for: .alignment)
                    Button { signingIn = false; accountReturnStep = 3; move(to: 1) } label: {
                        HStack { Text("Get started"); Spacer(); Image(systemName: "arrow.right") }
                            .font(.headline).dynamicTypeSize(...DynamicTypeSize.accessibility1).padding(20).frame(maxWidth: .infinity).foregroundStyle(Color.black)
                            .background(.white, in: .capsule)
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("onboarding-start")
                    Button("Already have an account? Sign in") { signingIn = true; accountReturnStep = 0; move(to: 4) }.font(.subheadline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("onboarding-sign-in")
                    Button("Explore first") { move(to: 5) }.font(.subheadline).dynamicTypeSize(...DynamicTypeSize.accessibility1).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("onboarding-explore")
                    Text("Mandarin Oriental, Bangkok · Hotel photography").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity)
                }.padding(.horizontal, 26).padding(.bottom, 12)
            }.foregroundStyle(.white)
        }
    }
    private func welcomeFeature(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.caption).foregroundStyle(.white.opacity(0.88))
    }
    private var preferences: some View {
        VStack(spacing: 0) {
            HStack {
                Button { move(to: step - 1) } label: { Image(systemName: "arrow.left").frame(width: 42, height: 42) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Previous step").accessibilityIdentifier("onboarding-back")
                Spacer()
                Text("YOUR SEUR").font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(Color.bronze).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                Spacer()
                Button(review ? "Done" : "Skip") { if review { dismiss() } else { move(to: 4) } }.font(.subheadline).frame(minWidth: 42, minHeight: 44).accessibilityIdentifier("onboarding-skip")
            }.padding(.horizontal, 24).padding(.top, 8)
            HStack(spacing: 7) {
                ForEach(1...(review ? 3 : 6), id: \.self) { value in Capsule().fill(value <= step ? Color.bronze : Color.bronze.opacity(0.15)).frame(height: 3) }
            }.padding(.horizontal, 27).padding(.top, 20).padding(.bottom, 6).accessibilityElement(children: .ignore).accessibilityLabel("Step \(step) of \(review ? 3 : 6)")
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: step == 1 ? "01 / Your kind of journey" : step == 2 ? "02 / A taste of you" : "03 / Somewhere in mind")
                        Editorial(step == 1 ? "What makes a trip\nunforgettable?" : step == 2 ? "Great journeys\nhave great tables." : "Where would you\nlove to begin?", size: 36)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1).accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused).accessibilityIdentifier("onboarding-title")
                        Text(step == 1 ? "Choose what draws you in. There’s no wrong way to get away." : step == 2 ? "Pick the cuisines you love. We’ll keep them close when you explore hotel dining." : "Choose a starting point for your collection. The rest of the world can wait—or not.")
                            .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                    }
                    if step == 1 { interestChoices }
                    else if step == 2 { diningChoices }
                    else { destinationChoices }
                    Label("Optional. Saved on this device. Change anytime.", systemImage: "slider.horizontal.3").font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
                }.padding(26).id(step)
            }.scrollIndicators(.hidden)
            VStack(spacing: 9) {
                Button { if review && step == 3 { dismiss() } else { move(to: step + 1) } } label: {
                    HStack { Text(step == 3 ? (review ? "Save preferences" : "Continue to your account") : "Continue"); Spacer(); Image(systemName: "arrow.right") }.onboardingPrimary()
                }.buttonStyle(PressStyle()).accessibilityIdentifier("onboarding-continue")
                Text(step == 3 ? "Your preferences are ready. The journey is yours." : "Choose as many or as few as you like.").font(.caption).foregroundStyle(.secondary).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12).background(Color.canvas)
        }
    }
    private var interestChoices: some View {
        VStack(spacing: 12) {
            ForEach(Array(OnboardingStore.interests.enumerated()), id: \.element) { index, interest in
                let selected = onboarding.profile.interests.contains(interest)
                Button { onboarding.toggleInterest(interest) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: symbols[index]).font(.system(size: 23, weight: .light)).foregroundStyle(Color.bronze).frame(width: 30)
                        VStack(alignment: .leading, spacing: 6) { Text(interest).font(.headline); Text(descriptions[index]).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        Spacer(minLength: 4)
                        selectionMark(selected)
                    }.padding(19).onboardingChoice(selected)
                }.buttonStyle(PressStyle()).accessibilityIdentifier("interest-\(index)").accessibilityValue(selected ? "Selected" : "Not selected").accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
    private var diningChoices: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(systemName: "fork.knife.circle").font(.system(size: 46, weight: .ultraLight)).foregroundStyle(Color.bronze)
                VStack(alignment: .leading, spacing: 7) { Text("The hotel is only half the story.").font(.system(.title3, design: .serif)); Text("Discover the restaurants, bars and cafés that make a stay worth savoring.").font(.caption).foregroundStyle(.secondary) }
            }.padding(20).cardSurface(cornerRadius: 25, emphasized: true)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(OnboardingStore.cuisines, id: \.self) { cuisine in
                    let selected = onboarding.profile.cuisines.contains(cuisine)
                    Button { onboarding.toggleCuisine(cuisine) } label: {
                        HStack { Text(cuisine).font(.subheadline.weight(.medium)); Spacer(minLength: 2); selectionMark(selected) }.padding(19).onboardingChoice(selected)
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("cuisine-\(cuisine)").accessibilityValue(selected ? "Selected" : "Not selected").accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("An open palate? Leave these unselected to explore every cuisine.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var destinationChoices: some View {
        VStack(spacing: 12) {
            Button { onboarding.chooseDestination("") } label: {
                HStack(spacing: 12) { Image(systemName: "globe.europe.africa").font(.title2).foregroundStyle(Color.bronze); Text("Let curiosity lead").font(.headline); Spacer(); selectionMark(onboarding.profile.destination.isEmpty) }.padding(19).onboardingChoice(onboarding.profile.destination.isEmpty)
            }.buttonStyle(PressStyle()).accessibilityIdentifier("destination-anywhere")
            ForEach([("Paris", "paris", "Art, elegance and extraordinary tables."), ("Bangkok", "bangkok", "Riverside legends. A city of flavor."), ("London", "london", "Grand traditions. A new perspective.")], id: \.0) { city, photo, subtitle in
                let selected = onboarding.profile.destination == city
                Button { onboarding.chooseDestination(selected ? "" : city) } label: {
                    HStack(spacing: 15) {
                        Image(photo).resizable().scaledToFill().frame(width: 68, height: 78).clipShape(.rect(cornerRadius: 16)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) { Text(city).font(.system(.title3, design: .serif)); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                        Spacer(minLength: 2); selectionMark(selected)
                    }.padding(12).onboardingChoice(selected)
                }.buttonStyle(PressStyle()).accessibilityIdentifier("destination-\(city)").accessibilityValue(selected ? "Selected" : "Not selected")
            }
            DisclosureGroup("More places to begin") {
                VStack(spacing: 8) {
                    ForEach(TravelStore.cities.filter { !["Paris", "Bangkok", "London"].contains($0) }, id: \.self) { city in
                        Button { onboarding.chooseDestination(city) } label: { HStack { Text(city); Spacer(); selectionMark(onboarding.profile.destination == city) }.padding(14).onboardingChoice(onboarding.profile.destination == city) }.buttonStyle(PressStyle())
                    }
                }.padding(.top, 10)
            }.padding(8)
            if !onboarding.profile.destination.isEmpty { Text("Your starting point: \(onboarding.profile.destination)").font(.footnote).foregroundStyle(Color.bronze) }
        }
    }
    private func selectionMark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 21, weight: .light)).foregroundStyle(selected ? Color.bronze : Color.secondary.opacity(0.4)).accessibilityHidden(true)
    }
    private func move(to value: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { step = value }
        if !review { onboarding.move(to: value) }
        titleFocused = true
    }
    private func finish() {
        onboarding.complete(); travel.selectedTab = 0
        if onboarding.profile.interests.contains("Memorable dining") { travel.category = .dining }
        if review { dismiss() }
    }
}

extension View {
    func onboardingPrimary() -> some View {
        self.font(.headline).dynamicTypeSize(...DynamicTypeSize.accessibility1).foregroundStyle(.white).padding(20).frame(maxWidth: .infinity)
            .background(Color.brandBronze, in: .capsule)
    }
    func onboardingChoice(_ selected: Bool) -> some View {
        self.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: 23, emphasized: selected)
            .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(selected ? Color.bronze : .clear, lineWidth: 1.4) }
            .contentShape(.rect(cornerRadius: 23))
    }
}

/// Onboarding shares the same verified account flow as Profile and Travel.
private struct OnboardingAccountView: View {
    var signingIn: Bool
    var onBack: () -> Void
    var onContinue: () -> Void
    var body: some View {
        NavigationStack {
            TravelAccountPage(register: !signingIn, onboardingBack: onBack, onboardingContinue: onContinue)
        }
    }
}


private struct OnboardingNotificationsView: View {
    var onBack: () -> Void
    var onContinue: () -> Void
    @State private var permission = OnboardingNotificationPermission()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) { Image(systemName: "arrow.left").font(.system(size: 18, weight: .medium)).frame(width: 42, height: 42) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Previous step")
                    .accessibilityIdentifier("onboarding-notifications-back")
                Spacer()
                Text("YOUR SEUR").font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(Color.bronze).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                Spacer()
                Color.clear.frame(width: 42, height: 42).accessibilityHidden(true)
            }.padding(.horizontal, 24).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !typeSize.isAccessibilitySize {
                    ZStack {
                        Circle().stroke(Color.bronze.opacity(0.12), lineWidth: 1).frame(width: 154, height: 154)
                        Circle().fill(Color.bronze.opacity(0.08)).frame(width: 112, height: 112)
                        Image(systemName: permission.isAllowed ? "bell.badge.fill" : "bell.badge")
                            .font(.system(size: 42, weight: .light)).foregroundStyle(Color.bronze)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "06 / Stay in the know").dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        Editorial("A little heads-up.\nA smoother journey.", size: 36).dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("onboarding-notifications-title")
                        Text("Get timely updates for the flights you choose to follow.")
                            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        notificationBenefit("Flight updates", detail: "Keep up with delays and schedule changes.", symbol: "airplane")
                        Divider()
                        notificationBenefit("Your choice, always", detail: "Follow the flights that matter to you. Change notification settings anytime.", symbol: "slider.horizontal.3")
                    }.padding(20).cardSurface(cornerRadius: 24)
                    VStack(alignment: .leading, spacing: 12) {
                        Label(permission.isAllowed ? "Notifications are on" : permission.status == .denied ? "Notifications are off" : "Notifications are optional", systemImage: permission.isAllowed ? "checkmark.circle" : "bell")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Color.bronze)
                            .accessibilityIdentifier("onboarding-notification-status")
                        if permission.status == .denied {
                            Text("You can turn them on later in Settings.").font(.caption).foregroundStyle(.secondary)
                            Button("Open notification settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                            }.font(.subheadline).accessibilityIdentifier("onboarding-notification-settings")
                        }
                        if let error = permission.error {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            Button("Try again") { Task { await permission.requestOnArrival() } }.disabled(permission.busy)
                        }
                    }
                }.padding(26)
            }.scrollIndicators(.hidden)
            Button(action: onContinue) {
                HStack { Text("Explore Seur"); Spacer(); Image(systemName: "arrow.right") }.onboardingPrimary()
            }.buttonStyle(PressStyle()).accessibilityIdentifier("onboarding-notifications-continue")
                .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12)
        }.background(Color.canvas)
            .task { await permission.requestOnArrival() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await permission.refresh() } }
            }
    }
    private func notificationBenefit(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3.weight(.light)).foregroundStyle(Color.bronze).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
