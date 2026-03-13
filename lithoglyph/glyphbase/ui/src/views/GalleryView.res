// SPDX-License-Identifier: PMPL-1.0-or-later
// Gallery View

open Types

type galleryLayout = Grid | Masonry

type galleryCard = {
  row: row,
  imageUrl: option<string>,
  title: string,
  fields: array<(string, cellValue)>,
}

@react.component
let make = (
  ~tableId: string,
  ~coverFieldId: option<string>=?,
  ~rows: array<row>,
  ~fields: array<fieldConfig>,
  ~onCardClick: option<row => unit>=?,
  ~layout: galleryLayout=Grid,
) => {
  let (selectedCard, setSelectedCard) = React.useState(() => None)

  // Get primary field for card titles
  let primaryField = fields->Array.find(f => f.name == "Title" || f.name == "Name")
  let primaryFieldId = switch primaryField {
  | Some(f) => f.id
  | None => fields->Array.get(0)->Option.mapOr("", f => f.id)
  }

  // Convert rows to gallery cards
  let cards = rows->Array.map(row => {
    // Get cover image URL
    let imageUrl = switch coverFieldId {
    | Some(fieldId) =>
      switch row.cells->Dict.get(fieldId) {
      | Some({value: AttachmentValue(attachments)}) =>
        attachments->Array.get(0)->Option.map(att => att.url)
      | Some({value: UrlValue(url)}) => Some(url)
      | _ => None
      }
    | None => None
    }

    // Get title
    let title = switch row.cells->Dict.get(primaryFieldId) {
    | Some({value: TextValue(text)}) => text
    | _ => `Card ${row.id}`
    }

    // Get first 3 non-cover fields for card metadata
    let cardFields =
      fields
      ->Array.filter(f =>
        f.id != primaryFieldId &&
        Some(f.id) != coverFieldId &&
        switch f.fieldType {
        | Formula(_) => false
        | _ => true
        }
      )
      ->Array.slice(~start=0, ~end=3)
      ->Array.filterMap(field => {
        row.cells->Dict.get(field.id)->Option.map(cell => (field.name, cell.value))
      })

    {row, imageUrl, title, fields: cardFields}
  })

  // Handle card click
  let handleCardClick = (card: galleryCard) => {
    switch onCardClick {
    | Some(handler) => handler(card.row)
    | None => setSelectedCard(_ => Some(card))
    }
  }

  // Render field value as string
  let renderFieldValue = (value: cellValue): string => {
    switch value {
    | TextValue(text) => text
    | NumberValue(num) => Float.toString(num)
    | DateValue(date) => date->Date.toLocaleDateString
    | CheckboxValue(checked) => checked ? "✓" : "✗"
    | SelectValue(option) => option
    | MultiSelectValue(options) => options->Array.join(", ")
    | UrlValue(url) => url
    | EmailValue(email) => email
    | AttachmentValue(attachments) => `${attachments->Array.length->Int.toString} file(s)`
    | _ => "" // Handle remaining variants
    }
  }

  // Render gallery card
  let renderCard = (card: galleryCard) => {
    <div key={card.row.id} className="gallery-card" onClick={_ => handleCardClick(card)}>
      {switch card.imageUrl {
      | Some(url) =>
        <div className="gallery-card-image">
          <img src={url} alt={card.title} />
        </div>
      | None =>
        <div className="gallery-card-image gallery-card-no-image">
          <div className="gallery-card-placeholder"> {React.string("📷")} </div>
        </div>
      }}
      <div className="gallery-card-content">
        <div className="gallery-card-title"> {React.string(card.title)} </div>
        <div className="gallery-card-fields">
          {card.fields
          ->Array.map(((fieldName, value)) => {
            <div key={fieldName} className="gallery-card-field">
              <div className="gallery-card-field-name"> {React.string(fieldName ++ ":")} </div>
              <div className="gallery-card-field-value">
                {React.string(renderFieldValue(value))}
              </div>
            </div>
          })
          ->React.array}
        </div>
      </div>
    </div>
  }

  // Render card detail modal
  let renderDetailModal = (card: galleryCard) => {
    <div className="gallery-modal-overlay" onClick={_ => setSelectedCard(_ => None)}>
      <div className="gallery-modal" onClick={evt => evt->ReactEvent.Mouse.stopPropagation}>
        <button
          className="gallery-modal-close"
          onClick={_ => setSelectedCard(_ => None)}
          ariaLabel="Close"
        >
          {React.string("×")}
        </button>
        {switch card.imageUrl {
        | Some(url) =>
          <div className="gallery-modal-image">
            <img src={url} alt={card.title} />
          </div>
        | None => React.null
        }}
        <div className="gallery-modal-content">
          <h2 className="gallery-modal-title"> {React.string(card.title)} </h2>
          <div className="gallery-modal-fields">
            {fields
            ->Array.filterMap(field => {
              card.row.cells->Dict.get(field.id)->Option.map(cell => (field, cell))
            })
            ->Array.map(((field, cell)) => {
              <div key={field.id} className="gallery-modal-field">
                <div className="gallery-modal-field-name"> {React.string(field.name)} </div>
                <div className="gallery-modal-field-value">
                  {React.string(renderFieldValue(cell.value))}
                </div>
              </div>
            })
            ->React.array}
          </div>
        </div>
      </div>
    </div>
  }

  <div className="gallery-view">
    <div
      className={`gallery-grid ${layout == Masonry
          ? "gallery-grid-masonry"
          : "gallery-grid-standard"}`}
    >
      {cards->Array.map(renderCard)->React.array}
    </div>
    {switch selectedCard {
    | Some(card) => renderDetailModal(card)
    | None => React.null
    }}
  </div>
}
