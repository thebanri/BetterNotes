#pragma once
#include <QString>

void platformCopyToClipboard(const QString& text);
QString platformGetClipboardText();
int platformCursorGlobalX();
int platformCursorGlobalY();
bool platformSetApplicationIcon();
void platformSetActivationToken(const QString& token);
QString platformPicturesFolder();
QString platformDocumentsFolder();
QString platformClipboardImageToFile();
bool platformCopyImageFile(const QString& path);
QString platformClipboardImageUrls();
