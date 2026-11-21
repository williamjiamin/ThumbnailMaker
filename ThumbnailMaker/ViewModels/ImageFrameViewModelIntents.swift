//
//  ImageFrameViewModelIntents.swift
//  ThumbnailMaker
//
//  FEATURE-03: discrete, immediately-undoable framing intents for both
//  editors. Each intent settles any pending debounced edit first, applies the
//  recipe, then settles again, so one call is exactly one undo step. The
//  image bytes are never touched.
//

import Foundation

extension SimpleMakerViewModel {
    /// Returns false (and changes nothing) when there is no background image
    /// to frame or the recipe is unchanged.
    @discardableResult
    func setImageFrameRecipe(_ recipe: ThumbnailImageFrameRecipe) -> Bool {
        guard simpleMakerConfiguration.selectedImage != nil,
              simpleMakerConfiguration.imageRecipe != recipe else { return false }
        commitEditorStateNow()
        simpleMakerConfiguration.imageRecipe = recipe
        commitEditorStateNow()
        return true
    }

    @discardableResult
    func resetImageFrame() -> Bool {
        setImageFrameRecipe(.identity)
    }
}

extension PremiumMakerViewModel {
    @discardableResult
    func setImageFrameRecipe(_ recipe: ThumbnailImageFrameRecipe) -> Bool {
        guard premiumMakerConfiguration.selectedImage != nil,
              premiumMakerConfiguration.imageRecipe != recipe else { return false }
        commitEditorStateNow()
        premiumMakerConfiguration.imageRecipe = recipe
        commitEditorStateNow()
        return true
    }

    @discardableResult
    func resetImageFrame() -> Bool {
        setImageFrameRecipe(.identity)
    }
}
