-- | Rendering of templates
module Text.PDF.Slave.Render(
    PDFContent
  , renderTemplateToPDF
  -- * Low-level
  , DepFlags
  , DepFlag(..)
  , renderPdfTemplate
  , renderTemplate
  , renderTemplateDep
  ) where

import Data.ByteString (ByteString)
import Data.Set (Set)
import GHC.Generics
import Prelude hiding (FilePath)
import Shelly

import qualified Data.Foldable as F
import qualified Data.Set as S

import Text.PDF.Slave.Template

-- | Contents of PDF file
type PDFContent = ByteString

-- | Render template and return content of resulted PDF file
renderTemplateToPDF :: TemplateFile -- ^ Input template
  -> FilePath -- ^ Base directory
  -> Sh PDFContent -- ^ Output PDF file
renderTemplateToPDF t@TemplateFile{..} baseDir = withTmpDir $ \outputFolder -> do
  renderPdfTemplate t baseDir outputFolder
  readBinary (outputFolder </> templateFileName <.> "pdf")

-- | Low-level render of template from .htex to .pdf that is recursively used for dependencies
renderPdfTemplate :: TemplateFile -- ^ Template to render
  -> FilePath -- ^ Base directory
  -> FilePath -- ^ Output folder
  -> Sh ()
renderPdfTemplate t@TemplateFile{..} baseDir outputFolder = do
  flags <- renderTemplate t baseDir outputFolder
  -- define commands of compilation pipe
  let pdflatex = bash "pdflatex" [
          "-synctex=1"
        , "-interaction=nonstopmode"
        , toTextArg $ outputFolder </> templateFileName <.> "tex" ]
      bibtex = bash "bibtex" [
          toTextArg $ outputFolder </> templateFileName <.> "aux" ]
  -- read flags and construct pipe
  _ <- if S.member NeedBibtex flags
    then pdflatex -|- bibtex -|- pdflatex
    else pdflatex
  return ()

-- | Low-level render of template from .htex to .tex that is recursively used for dependencies
renderTemplate :: TemplateFile -- ^ Template to render
  -> FilePath -- ^ Base directory
  -> FilePath -- ^ Output folder
  -> Sh DepFlags -- ^ Flags that affects compilation upper in the deptree
renderTemplate TemplateFile{..} baseDir outputFolder = do
  depFlags <- traverse (renderTemplateDep baseDir outputFolder) templateFileDeps
  _ <- bash "haskintex" [toTextArg $ baseDir </> templateFileBody]
  return $ F.foldMap id depFlags -- merge flags

-- | Collected dependency markers (for instance, that we need bibtex compilation)
type DepFlags = Set DepFlag

-- | Dependency marker that is returned from 'renderTemplateDep'
data DepFlag = NeedBibtex -- ^ We need a bibtex compliation
  deriving (Generic, Show, Ord, Eq)

-- | Render template dependency
renderTemplateDep :: FilePath -- ^ Base directory
  -> FilePath  -- ^ Output folder
  -> TemplateDependencyFile -- ^ Dependency type
  -> Sh DepFlags
renderTemplateDep baseDir outputFolder dep = case dep of
  BibtexDepFile _ -> return $ S.singleton NeedBibtex
  TemplateDepFile template -> renderTemplate template baseDir outputFolder
  TemplatePdfDepFile template -> do
    renderPdfTemplate template baseDir outputFolder
    return mempty
  OtherDepFile _ -> return mempty