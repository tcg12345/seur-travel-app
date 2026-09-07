import SwiftUI

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
                MembershipPreviewView(onBack: { move(to: 4) }, onFinish: finish)
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
                        Image(systemName: "a.circle").font(.system(size: 25, weight: .ultraLight))
                        Text("AURUM").font(.system(size: 15, weight: .medium)).tracking(6)
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
                Text("YOUR AURUM").font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(Color.bronze).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                Spacer()
                Button(review ? "Done" : "Skip") { if review { dismiss() } else { move(to: 4) } }.font(.subheadline).frame(minWidth: 42, minHeight: 44).accessibilityIdentifier("onboarding-skip")
            }.padding(.horizontal, 24).padding(.top, 8)
            HStack(spacing: 7) {
                ForEach(1...(review ? 3 : 5), id: \.self) { value in Capsule().fill(value <= step ? Color.bronze : Color.bronze.opacity(0.15)).frame(height: 3) }
            }.padding(.horizontal, 27).padding(.top, 20).padding(.bottom, 6).accessibilityElement(children: .ignore).accessibilityLabel("Step \(step) of \(review ? 3 : 5)")
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
            }.padding(20).background(Color.bronze.opacity(0.08), in: .rect(cornerRadius: 25))
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
            .background(Color(red: 0.24, green: 0.34, blue: 0.30), in: .capsule)
    }
    func onboardingChoice(_ selected: Bool) -> some View {
        self.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.bronze.opacity(0.08) : Color.cardSurface, in: .rect(cornerRadius: 23))
            .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(selected ? Color.bronze : .clear, lineWidth: 1.4) }
            .contentShape(.rect(cornerRadius: 23))
    }
}

/// Creates the same cloud account used by Travel, without storing credentials in onboarding drafts.
private struct OnboardingAccountView: View {
    @Environment(TravelAPI.self) private var api
    @State var signingIn: Bool
    var onBack: () -> Void
    var onContinue: () -> Void
    @State private var name = ""
    @State private var handle = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var submitting = false
    @State private var restoring = true
    @State private var message: String?
    @FocusState private var focused: Field?
    private enum Field: Hashable { case name, handle, password, confirmation }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) { Image(systemName: "arrow.left").frame(width: 42, height: 42) }
                    .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Previous step")
                    .accessibilityIdentifier("onboarding-account-back").disabled(submitting)
                Spacer()
                Text("YOUR AURUM").font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(Color.bronze)
                Spacer()
                Image(systemName: "lock.shield").foregroundStyle(Color.bronze).frame(width: 42, height: 42).accessibilityHidden(true)
            }.dynamicTypeSize(...DynamicTypeSize.xxxLarge).padding(.horizontal, 24).padding(.top, 8)
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "A place for your journeys").dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        Editorial(api.isSignedIn ? "Make yourself\nat home." : signingIn ? "Welcome\nback." : "Your next chapter\nstarts here.", size: 36)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1).accessibilityAddTraits(.isHeader).accessibilityIdentifier("onboarding-account-title")
                        Text("Save trips to the cloud, share discoveries with friends, and keep your travel plans close.")
                            .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                    }.padding(.vertical, 10)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                if let account = api.account, api.isSignedIn {
                    Section {
                        HStack(spacing: 16) {
                            Image(systemName: "checkmark.seal.fill").font(.title).foregroundStyle(Color.bronze)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(account.name).font(.headline)
                                Text("Signed in as @" + account.handle).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 12)
                    }
                } else {
                    Section {
                        if !signingIn {
                            accountField("Your name") {
                                TextField("Name", text: $name).textContentType(.name).focused($focused, equals: .name)
                                    .submitLabel(.next).onSubmit { focused = .handle }.accessibilityIdentifier("onboarding-account-name")
                            }
                        }
                        accountField("Username") {
                            TextField("Choose a username", text: $handle).textContentType(.username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .handle)
                                .submitLabel(.next).onSubmit { focused = .password }.accessibilityIdentifier("onboarding-account-handle")
                        }
                        accountField("Password") {
                            SecureField("12 or more characters", text: $password).textContentType(signingIn ? .password : .newPassword)
                                .focused($focused, equals: .password).submitLabel(signingIn ? .go : .next)
                                .onSubmit { if signingIn { submit() } else { focused = .confirmation } }
                                .accessibilityIdentifier("onboarding-account-password")
                        }
                        if !signingIn {
                            accountField("Confirm password") {
                                SecureField("Enter your password again", text: $confirmation).textContentType(.newPassword)
                                    .focused($focused, equals: .confirmation).submitLabel(.go).onSubmit { submit() }
                                    .accessibilityIdentifier("onboarding-account-confirmation")
                            }
                        }
                    } footer: {
                        Text("Use 3–32 letters, numbers or underscores for your username. You’ll use it to sign in and connect with friends.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).disabled(submitting)
                    Section {
                        Button(signingIn ? "New here? Create an account" : "Already a member? Sign in") {
                            focused = nil; signingIn.toggle(); message = nil; password = ""; confirmation = ""
                        }.font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("onboarding-account-mode").disabled(submitting)
                    }.listRowBackground(Color.clear)
                }
            }.scrollContentBackground(.hidden).scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("onboarding-account-error")
                }
                Button { if api.isSignedIn { onContinue() } else { submit() } } label: {
                    HStack {
                        if submitting || restoring { ProgressView().tint(.white) }
                        Text(api.isSignedIn ? "Continue to membership" : submitting ? "Connecting…" : signingIn ? "Sign in" : "Create account")
                        Spacer(); Image(systemName: "arrow.right")
                    }.onboardingPrimary()
                }.buttonStyle(PressStyle()).disabled(submitting || restoring)
                    .accessibilityIdentifier("onboarding-account-submit")
                if !api.isSignedIn {
                    Button("Continue without an account", action: onContinue).font(.subheadline).frame(minHeight: 44)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1).accessibilityIdentifier("onboarding-account-skip").disabled(submitting)
                } else {
                    Text("Your account is ready. Membership is optional.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 24).padding(.vertical, 12).background(Color.canvas)
        }
        .task { defer { restoring = false }; try? await api.refresh() }
        .onDisappear { password = ""; confirmation = "" }

    }

    private func accountField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content().font(.body).frame(minHeight: 24)
        }.padding(20)
    }

    private func submit() {
        guard !submitting && !restoring else { return }
        message = nil
        let username = handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard username.range(of: "^[a-z0-9_]{3,32}$", options: .regularExpression) != nil else {
            message = "Choose a username with 3–32 letters, numbers or underscores."; return
        }
        guard password.count >= 12 && password.count <= 256 else {
            message = "Your password needs 12–256 characters."; return
        }
        guard signingIn || password == confirmation else { message = "Your passwords don’t match. Please try again."; return }
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard signingIn || !displayName.isEmpty && displayName.count <= 100 else { message = "Enter your name (up to 100 characters)."; return }
        focused = nil; submitting = true
        Task { @MainActor in
            defer { submitting = false }
            do {
                try await api.authenticate(handle: username, name: displayName, password: password, register: !signingIn)
                password = ""; confirmation = ""
                onContinue()
            } catch { message = error.localizedDescription }
        }
    }
}
