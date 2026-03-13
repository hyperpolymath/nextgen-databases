// SPDX-License-Identifier: PMPL-1.0-or-later
// Core types for Glyphbase

type fieldType =
  | Text
  | Number
  | Select(array<string>)
  | MultiSelect(array<string>)
  | Date
  | DateTime
  | Checkbox
  | Link(string) // table id
  | Attachment
  | Formula(string)
  | Rollup(string, string) // linked field, aggregation
  | Lookup(string, string) // linked field, lookup field
  | Url
  | Email
  | Phone
  | Rating
  | Barcode

type fieldConfig = {
  id: string,
  name: string,
  fieldType: fieldType,
  required: bool,
  defaultValue: option<string>,
  description: option<string>,
}

// Attachment file object
type attachmentFile = {
  id: string,
  name: string,
  url: string,
  mimeType: string,
  size: int,
}

type cellValue =
  | TextValue(string)
  | NumberValue(float)
  | SelectValue(string)
  | MultiSelectValue(array<string>)
  | DateValue(Date.t)
  | CheckboxValue(bool)
  | LinkValue(array<string>) // row ids
  | AttachmentValue(array<attachmentFile>)
  | UrlValue(string) // URL field type
  | EmailValue(string) // Email field type
  | PhoneValue(string) // Phone field type
  | NullValue

type provenanceEntry = {
  timestamp: string,
  userId: string,
  userName: string,
  previousValue: option<cellValue>,
  newValue: cellValue,
  rationale: option<string>,
}

type cell = {
  fieldId: string,
  value: cellValue,
  provenance: array<provenanceEntry>,
}

type row = {
  id: string,
  cells: dict<cell>,
  createdAt: string,
  updatedAt: string,
}

type table = {
  id: string,
  name: string,
  fields: array<fieldConfig>,
  primaryFieldId: string,
}

type viewType =
  | Grid
  | Kanban(string) // group by field id
  | Calendar(string) // date field id
  | Gallery(string) // image field id
  | Form

type viewConfig = {
  id: string,
  name: string,
  tableId: string,
  viewType: viewType,
  visibleFields: array<string>,
  sortBy: option<(string, [#Asc | #Desc])>,
  filterBy: option<string>, // FQL filter expression
}

type base = {
  id: string,
  name: string,
  description: option<string>,
  icon: option<string>,
  tables: array<table>,
  views: array<viewConfig>,
  createdAt: string,
  updatedAt: string,
}
