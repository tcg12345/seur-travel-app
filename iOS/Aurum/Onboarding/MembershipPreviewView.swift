import SwiftUI

/// A local design preview. This view deliberately has no StoreKit or payment integration.
struct MembershipPreviewView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var onBack: (() -> Void)? = nil
    let onFinish: () -> Void
    @State private var selected: PreviewPlan = .annual
    @State private var confirming = false
    @State private var success = false
    @State private var information = false
    @State private var restoreMessage: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onBack {
                    Button(action: onBack) { Image(systemName: "arrow.left").frame(width: 42, height: 42) }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Previous step").accessibilityIdentifier("membership-back")
                }
                Spacer()
                Label("MEMBERSHIP PREVIEW", systemImage: "sparkle").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(Color.bronze)
                Spacer()
                Button(action: onFinish) { Image(systemName: "xmark").frame(width: 42, height: 42) }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Continue without membership").accessibilityIdentifier("membership-close")
            }.padding(.horizontal, 24).padding(.top, 9)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if success { successContent }
                    else {
                        membershipCard
                        VStack(alignment: .leading, spacing: 10) {
                            Editorial("A little more\nextraordinary.", size: 32).dynamicTypeSize(...DynamicTypeSize.accessibility1).accessibilityAddTraits(.isHeader).accessibilityIdentifier("membership-title")
                            Text("Meet Seur Reserve. A preview of a more considered way to travel.").font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
                        }
                        VStack(spacing: 11) { ForEach(PreviewPlan.allCases) { plan in planRow(plan) } }
                        VStack(alignment: .leading, spacing: 17) {
                            benefit("Exceptional stays & hotel dining", detail: "Keep remarkable places in one collection.", symbol: "fork.knife")
                            benefit("Every detail, beautifully together", detail: "Plan your days, stays and flights.", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                            benefit("Memories worth returning to", detail: "Journal, rate and share your journeys.", symbol: "book.closed")
                        }
                        Text("Illustrative prices in USD. All current app features remain available without a membership.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Restore preview") { restore() }.accessibilityIdentifier("membership-restore")
                            Spacer()
                            Button("About this preview") { information = true }
                        }.font(.caption).frame(minHeight: 40)
                    }
                }.padding(26)
            }.scrollIndicators(.hidden)
            VStack(spacing: 8) {
                Button {
                    if success { onFinish() } else { confirming = true }
                } label: {
                    HStack { Text(success ? (onBack == nil ? "Explore Seur" : "Continue") : typeSize.isAccessibilitySize ? "Preview plan" : "Preview \(selected.title.lowercased()) membership"); Spacer(); Image(systemName: "arrow.right") }.onboardingPrimary()
                }.buttonStyle(PressStyle()).accessibilityIdentifier(success ? "membership-finish" : "membership-preview")
                if !success { Button("Continue without membership", action: onFinish).font(.subheadline).frame(minHeight: 36).accessibilityIdentifier("membership-skip") }
                Text("No charge. No trial. No automatic renewal.").font(.caption2).foregroundStyle(.secondary).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 10).background(Color.canvas)
        }.background(Color.canvas)
            .onAppear { selected = onboarding.profile.previewPlan ?? .annual }
            .sensoryFeedback(.selection, trigger: selected)
            .sheet(isPresented: $confirming) { confirmation }
            .sheet(isPresented: $information) { previewInformation }
            .alert("Restore membership preview", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) { Button("OK") { restoreMessage = nil } } message: { Text(restoreMessage ?? "") }
    }
    private var membershipCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 27).fill(LinearGradient(colors: [Color.brandInk, Color.brandBronze], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "globe.europe.africa").font(.system(size: 150, weight: .ultraLight)).foregroundStyle(.white.opacity(0.09)).rotationEffect(.degrees(-15)).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 10) { SeurLogo(size: 30); Text("SEUR").font(.system(size: 11, weight: .medium)).tracking(4); Spacer(); Image(systemName: "sparkle").font(.title2) }
                HStack(alignment: .bottom) { Text("Reserve").font(.system(size: 34, design: .serif)); Spacer(); Text("DESIGN PREVIEW").font(.system(size: 8, weight: .medium)).tracking(1.8) }
            }.foregroundStyle(Color(red: 0.93, green: 0.88, blue: 0.75)).padding(24)
        }.frame(height: 136).accessibilityElement(children: .combine)
    }
    private func benefit(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 21, weight: .light)).foregroundStyle(Color.bronze).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.subheadline.weight(.medium)); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func planRow(_ plan: PreviewPlan) -> some View {
        Button { selected = plan } label: {
            HStack(spacing: 12) {
                Image(systemName: selected == plan ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.bronze).font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) { Text(plan.title).font(.headline); if plan == .annual { Text("SAVE 33%").font(.system(size: 8, weight: .bold)).padding(6).background(Color.bronze.opacity(0.12), in: .capsule).foregroundStyle(Color.bronze) } }
                    Text(plan.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: 4) { Text(plan.price).font(.system(.title3, design: .serif)); Text(plan.interval).font(.caption).foregroundStyle(.secondary) }
            }.padding(17).onboardingChoice(selected == plan)
        }.buttonStyle(PressStyle()).accessibilityIdentifier("membership-\(plan.rawValue)").accessibilityValue(selected == plan ? "Selected" : "Not selected").accessibilityAddTraits(selected == plan ? .isSelected : [])
    }
    private var confirmation: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label("SIMULATED SUBSCRIPTION", systemImage: "sparkles").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(Color.bronze)
                    Editorial("Try the feeling.\nKeep it effortless.", size: 32)
                    LabeledContent("Seur Reserve", value: selected.title).font(.headline)
                    LabeledContent("Example price", value: "\(selected.price) \(selected.interval)")
                    LabeledContent("Charged today", value: "$0.00").foregroundStyle(Color.bronze)
                    Text("This is a design preview. Confirming only saves your chosen plan on this device. It does not create a subscription, start a trial, request payment details or charge you now or later.").font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                    Button {
                        onboarding.selectPreview(selected); confirming = false
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { success = true }
                    } label: { Text("Confirm preview · no charge").onboardingPrimary() }.buttonStyle(PressStyle()).accessibilityIdentifier("membership-confirm")
                    Button("Not now") { confirming = false }.frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("membership-cancel")
                }.padding(26)
            }.background(Color.canvas).navigationTitle("Preview your plan").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { confirming = false } } }
        }.presentationDetents([.large])
    }
    private var successContent: some View {
        VStack(alignment: .leading, spacing: 25) {
            Image(systemName: "checkmark.seal").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(Color.bronze).padding(.top, 28)
            Eyebrow(text: "Your preview is ready")
            Editorial("Welcome to\nyour next chapter.", size: 39).accessibilityIdentifier("membership-success")
            Text("Your \(selected.title.lowercased()) Reserve preview is saved on this device. Nothing has been purchased.").font(.body).foregroundStyle(.secondary).lineSpacing(4)
            membershipCard
            Text("Revisit your preferences or change the preview plan anytime in Your workspace.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var previewInformation: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Editorial("Just a preview.", size: 34)
                    Text("Seur Reserve is an interactive subscription design, not an offer for sale. Prices and membership packaging are illustrative.")
                    Text("No Apple purchase sheet, payment processing, billing, trial, renewal or subscription entitlement is connected. Restore preview reads only a previously saved preview on this device; it cannot restore an App Store purchase.")
                    Text("Travel preferences and the selected preview plan are stored locally. Account creation and sign-in connect to Seur Cloud. No notification, tracking or location permission is requested.")
                    Text("All existing features stay available. Live provider features still depend on their separate backend configuration.")
                }.font(.subheadline).lineSpacing(4).padding(26)
            }.background(Color.canvas).navigationTitle("About this preview").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { information = false } } }
        }
    }
    private func restore() {
        if let plan = onboarding.profile.previewPlan { selected = plan; restoreMessage = "Your \(plan.title.lowercased()) preview is restored from this device. No purchase or active subscription exists." }
        else { restoreMessage = "No preview has been saved on this device. There are no App Store purchases to restore in this demo." }
    }
}
