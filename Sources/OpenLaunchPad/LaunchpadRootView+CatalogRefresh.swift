import AppCore
import AppKit

extension LaunchpadRootView {
    func refreshApplicationsFromDisk() async {
        let discovery = await catalog.refreshOutcome()
        guard !isCatalogUpdateBlocked else {
            refreshWhenInteractionEnds()
            return
        }

        let document: LauncherLayoutDocument
        do {
            let reconciliation = try await layoutStore.reconcileAndCommit(
                applications: discovery.applications, completeness: discovery.completeness)
            scheduleMissingApplicationReview(after: reconciliation.reviewDelay)
            document = reconciliation.document
        } catch {
            document =
                LauncherLayoutReconciler.reconcile(
                    layoutDocument, with: discovery.applications, completeness: discovery.completeness
                ).document
        }

        // A gesture can begin while the store is writing.
        guard !isCatalogUpdateBlocked else {
            refreshWhenInteractionEnds()
            return
        }
        applyCatalog(applications: discovery.applications, document: document)
    }

    /// Restores the layout after a failed save. If another writer has advanced
    /// the store meanwhile, the snapshot's revision is stale and a view that kept
    /// it could never save again, so the stored layout is used instead.
    func restoreLayout(afterFailedSaveFrom snapshot: LauncherLayoutDocument) async {
        let stored = try? await layoutStore.load()
        layoutDocument = stored.flatMap { $0.revision == snapshot.revision ? nil : $0 } ?? snapshot
        invalidatePageSurfaceCache()
    }

    /// A new catalog replaces the layout document and every page surface. That
    /// would invalidate the draft of a drag and close the folder being viewed.
    private var isCatalogUpdateBlocked: Bool {
        dragInteraction.state != .idle || dragSession != nil || folderItemDragSession != nil || isCommittingLayout
            || isFinishingDragVisuals || isResettingLayout || isCommittingFolderTitle || openFolderID != nil
            || isPageTransitionActive
    }

    private func applyCatalog(applications: [ApplicationRecord], document: LauncherLayoutDocument) {
        guard applications != self.applications || document != layoutDocument else { return }
        self.applications = applications
        layoutDocument = document

        selectedIndex = -1
        if searchField.stringValue.isEmpty, let metrics = currentMetrics {
            currentPage = min(currentPage, max(0, pageProjection(metrics: metrics).pageCount - 1))
        } else {
            currentPage = 0
        }
        resetPageTransition()
        invalidatePageSurfaceCache()
        needsLayout = true

        // While hidden, the next opening needs the new first page's icons.
        scheduleIdleFirstPageIconWarm()
    }

    private func refreshWhenInteractionEnds() {
        guard catalogRefreshTasks.deferred == nil else { return }
        catalogRefreshTasks.deferred = Task { @MainActor [weak self] in
            repeat {
                try? await Task.sleep(for: .milliseconds(250))
            } while self?.isCatalogUpdateBlocked == true
            guard let self else { return }
            catalogRefreshTasks.deferred = nil
            await refreshApplicationsFromDisk()
        }
    }

    private func scheduleMissingApplicationReview(after delay: TimeInterval?) {
        catalogRefreshTasks.missingApplicationReview?.cancel()
        catalogRefreshTasks.missingApplicationReview = nil
        guard let delay else { return }
        catalogRefreshTasks.missingApplicationReview = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay + 1))
            guard !Task.isCancelled, let self else { return }
            catalogRefreshTasks.missingApplicationReview = nil
            await refreshApplicationsFromDisk()
        }
    }
}
