/*
 The MIT License (MIT)

 Copyright (c) 2015-present Badoo Trading Limited.

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
*/

import UIKit
import Chatto
import ChattoAdditions

class DemoChatViewController: UIViewController {
    let baseChatViewController: BaseChatViewController
    let dataSource: DemoChatDataSource
    let keyboardUpdatesHandler: KeyboardUpdatesHandlerDelegate
    let messagesSelector = BaseMessagesSelector()

    private lazy var chatPanGestureRecogniserHandler: ChatPanGestureRecogniserHandler = {
        var panGestureHandlerConfig = CellPanGestureHandlerConfig.defaultConfig()
        panGestureHandlerConfig.allowReplyRevealing = true

        return ChatPanGestureRecogniserHandler(
            panGestureHandlerConfig: panGestureHandlerConfig,
            replyActionHandler: DemoReplyActionHandler(presentingViewController: self),
            replyFeedbackGenerator: ReplyFeedbackGenerator()
        )
    }()

    var messageSender: DemoChatMessageSender

    init(dataSource: DemoChatDataSource,
         shouldUseAlternativePresenter: Bool = false,
         shouldUseNewMessageArchitecture: Bool = false) {
        self.dataSource = dataSource
        self.messageSender = dataSource.messageSender

        let adapterConfig = ChatMessageCollectionAdapter.Configuration.default
        let presentersBuilder = Self.createPresenterBuilders(messageSender: self.messageSender, messageSelector: self.messagesSelector)

        let fallbackItemPresenterFactory: ChatItemPresenterFactoryProtocol
        if self.shouldUseNewMessageArchitecture {
            fallbackItemPresenterFactory = self.makeNewFallbackItemPresenterFactory()
        } else {
            fallbackItemPresenterFactory = DummyItemPresenterFactory()
        }

        let chatItemPresenterFactory = ChatItemPresenterFactory(
            presenterBuildersByType: presentersBuilder,
            fallbackItemPresenterFactory: fallbackItemPresenterFactory
        )
        let chatItemsDecorator = DemoChatItemsDecorator(messagesSelector: self.messagesSelector)
        let chatMessageCollectionAdapter = ChatMessageCollectionAdapter(
            chatItemsDecorator: chatItemsDecorator,
            chatItemPresenterFactory: chatItemPresenterFactory,
            chatMessagesViewModel: dataSource,
            configuration: adapterConfig,
            referenceIndexPathRestoreProvider: ReferenceIndexPathRestoreProviderFactory.makeDefault(),
            updateQueue: SerialTaskQueue()
        )
        let layout = ChatCollectionViewLayout()
        layout.layoutModelProvider = chatMessageCollectionAdapter
        let messagesViewController = ChatMessagesViewController(
            config: .default,
            layout: layout,
            messagesAdapter: chatMessageCollectionAdapter,
            style: .default,
            viewModel: dataSource
        )
        chatMessageCollectionAdapter.delegate = messagesViewController
        let chatInputItems = Self.createChatInputItems(
            dataSource: dataSource,
            shouldUseAlternativePresenter: shouldUseAlternativePresenter
        )
        let chatInputContainer = Self.makeChatInputPresenter(
            chatInputItems: chatInputItems,
            shouldUseAlternativePresenter: shouldUseAlternativePresenter
        )
        let keyboardTracker = KeyboardTracker(notificationCenter: .default)
        let keyboardHandler = KeyboardUpdatesHandler(keyboardTracker: keyboardTracker)

        self.keyboardUpdatesHandler = chatInputContainer.keyboardHandlerDelegate

        self.baseChatViewController = BaseChatViewController(
            inputBarPresenter: chatInputContainer.presenter,
            messagesViewController: messagesViewController,
            collectionViewEventsHandlers: [chatInputContainer.collectionHandler].compactMap { $0 },
            keyboardUpdatesHandler: keyboardHandler,
            viewEventsHandlers: [chatInputContainer.viewPresentationHandler].compactMap { $0 }
        )
        super.init(nibName: nil, bundle: nil)

        chatInputItems.forEach { ($0 as? PresenterChatInputItemProtocol)?.presentingController = self }
        messagesViewController.delegate = self.baseChatViewController
        chatInputContainer.presenter.viewController = self.baseChatViewController

        keyboardHandler.keyboardInputAdjustableViewController = self.baseChatViewController

        keyboardHandler.keyboardInfo.observe(self) { [weak keyboardHandlerDelegate = chatInputContainer.keyboardHandlerDelegate] _, keyboardInfo in
            keyboardHandlerDelegate?.didAdjustBottomMargin(to: keyboardInfo.bottomMargin, state: keyboardInfo.state)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupChatViewController()

        self.title = "Chat"
        self.messagesSelector.delegate = self
        self.chatPanGestureRecogniserHandler.chatViewController = self.baseChatViewController
    }

    func refreshContent() {
        self.baseChatViewController.refreshContent()
    }

    public func scrollToItem(withId id: String, position: UICollectionView.ScrollPosition, animated: Bool) {
        self.baseChatViewController.scrollToItem(withId: id, position: position, animated: animated)
    }

    private func setupChatViewController() {
        self.addChild(self.baseChatViewController)
        defer { self.baseChatViewController.didMove(toParent: self) }

        self.view.addSubview(self.baseChatViewController.view)
        self.baseChatViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.view.topAnchor.constraint(equalTo: self.baseChatViewController.view.topAnchor),
            self.view.trailingAnchor.constraint(equalTo: self.baseChatViewController.view.trailingAnchor),
            self.view.bottomAnchor.constraint(equalTo: self.baseChatViewController.view.bottomAnchor),
            self.view.leadingAnchor.constraint(equalTo: self.baseChatViewController.view.leadingAnchor),
        ])
    }

    private static func makeChatInputPresenter(chatInputItems: [ChatInputItemProtocol],
                                               shouldUseAlternativePresenter: Bool) -> ChatInputContainer {
        let chatInputView = ChatInputBar.loadNib()
        chatInputView.maxCharactersCount = 1000

        var appearance = ChatInputBarAppearance()
        appearance.sendButtonAppearance.title = NSLocalizedString("Send", comment: "")
        appearance.textInputAppearance.placeholderText = NSLocalizedString("Type a message", comment: "")

        guard shouldUseAlternativePresenter else {
            let presenter = BasicChatInputBarPresenter(
                chatInputBar: chatInputView,
                chatInputItems: chatInputItems,
                chatInputBarAppearance: appearance
            )
            let keyboardHandler = DefaultKeyboardHandler(presenter: presenter)

            return (presenter, keyboardHandler, nil, nil)
        }

        let presenter = ExpandableChatInputBarPresenter(
                chatInputBar: chatInputView,
                chatInputItems: chatInputItems,
                chatInputBarAppearance: appearance
            )

        return (presenter, presenter, presenter, nil)
    }

    private static func createChatInputItems(dataSource: DemoChatDataSource,
                                             shouldUseAlternativePresenter: Bool) -> [ChatInputItemProtocol] {
        var items = [ChatInputItemProtocol]()
        items.append(self.createTextInputItem(dataSource: dataSource))
        items.append(self.createPhotoInputItem(dataSource: dataSource))
        if shouldUseAlternativePresenter {
            items.append(self.customInputItem(dataSource: dataSource))
        }
        return items
    }

    static private func createPresenterBuilders(messageSender: DemoChatMessageSender,
                                                messageSelector: BaseMessagesSelector) -> [ChatItemType: [ChatItemPresenterBuilderProtocol]] {
        if self.shouldUseNewMessageArchitecture {
            self.makeNewPresenterBuilders()
        } else {
            self.makeOldPresenterBuilders(messageSender: messageSender, messageSelector: messageSelector)
        }
    }

    func createTextMessageViewModelBuilder() -> DemoTextMessageViewModelBuilder {
        return DemoTextMessageViewModelBuilder()
    }

    private func makeOldPresenterBuilders(messageSender: DemoChatMessageSender,
                                          messageSelector: BaseMessagesSelector) -> [ChatItemType: [ChatItemPresenterBuilderProtocol]] {
        let textMessagePresenter = TextMessagePresenterBuilder(
            viewModelBuilder: Self.createTextMessageViewModelBuilder(),
            interactionHandler: DemoMessageInteractionHandler(messageSender: messageSender, messagesSelector: messageSelector)
        )
        textMessagePresenter.baseMessageStyle = BaseMessageCollectionViewCellAvatarStyle()

        let photoMessagePresenter = PhotoMessagePresenterBuilder(
            viewModelBuilder: DemoPhotoMessageViewModelBuilder(),
            interactionHandler: DemoMessageInteractionHandler(messageSender: messageSender, messagesSelector: messageSelector)
        )
        photoMessagePresenter.baseCellStyle = BaseMessageCollectionViewCellAvatarStyle()

        let compoundPresenterBuilder = CompoundMessagePresenterBuilder(
            viewModelBuilder: DemoCompoundMessageViewModelBuilder(),
            interactionHandler: DemoMessageInteractionHandler(messageSender: messageSender, messagesSelector: messageSelector),
            accessibilityIdentifier: nil,
            contentFactories: [
                .init(DemoTextMessageContentFactory()),
                .init(DemoImageMessageContentFactory()),
                .init(DemoDateMessageContentFactory())
            ],
            decorationFactories: [
                .init(DemoEmojiDecorationViewFactory())
            ],
            baseCellStyle: BaseMessageCollectionViewCellAvatarStyle()
        )

        let compoundPresenterBuilder2 = CompoundMessagePresenterBuilder(
            viewModelBuilder: DemoCompoundMessageViewModelBuilder(),
            interactionHandler: DemoMessageInteractionHandler(messageSender: messageSender, messagesSelector: messageSelector),
            accessibilityIdentifier: nil,
            contentFactories: [
                .init(DemoTextMessageContentFactory()),
                .init(DemoImageMessageContentFactory()),
                .init(DemoInvisibleSplitterFactory()),
                .init(DemoText2MessageContentFactory())
            ],
            decorationFactories: [
                .init(DemoEmojiDecorationViewFactory())
            ],
            baseCellStyle: BaseMessageCollectionViewCellAvatarStyle()
        )

        return [
            DemoTextMessageModel.chatItemType: [textMessagePresenter],
            DemoPhotoMessageModel.chatItemType: [photoMessagePresenter],
            SendingStatusModel.chatItemType: [SendingStatusPresenterBuilder()],
            TimeSeparatorModel.chatItemType: [TimeSeparatorPresenterBuilder()],
            ChatItemType.compoundItemType: [compoundPresenterBuilder],
            ChatItemType.compoundItemType2: [compoundPresenterBuilder2]
        ]
    }

    private func makeNewFallbackItemPresenterFactory() -> ChatItemPresenterFactoryProtocol {
        fatalError()
    }

    private func makeNewPresenterBuilders() -> [ChatItemType: [ChatItemPresenterBuilderProtocol]] {
        fatalError()
    }

    private static func createTextInputItem(dataSource: DemoChatDataSource) -> TextChatInputItem {
        let item = TextChatInputItem()
        item.textInputHandler = { [weak dataSource] text in
            dataSource?.addTextMessage(text)
        }
        return item
    }

    private static func createPhotoInputItem(dataSource: DemoChatDataSource) -> PhotosChatInputItem {
        let item = PhotosChatInputItem()
        item.photoInputHandler = { [weak dataSource] image, _ in
            dataSource?.addPhotoMessage(image)
        }
        return item
    }

    private static func customInputItem(dataSource: DemoChatDataSource) -> ContentAwareInputItem {
        let item = ContentAwareInputItem()
        item.textInputHandler = { [weak dataSource] text in
            dataSource?.addTextMessage(text)
        }
        return item
    }
}

extension DemoChatViewController: MessagesSelectorDelegate {
    func messagesSelector(_ messagesSelector: MessagesSelectorProtocol, didSelectMessage: MessageModelProtocol) {
        self.baseChatViewController.refreshContent()
    }

    func messagesSelector(_ messagesSelector: MessagesSelectorProtocol, didDeselectMessage: MessageModelProtocol) {
        self.baseChatViewController.refreshContent()
    }
}

private protocol PresenterChatInputItemProtocol: AnyObject {
    var presentingController: UIViewController? { get set }
}

extension PhotosChatInputItem: PresenterChatInputItemProtocol {}

typealias ChatInputContainer = (
    presenter: BaseChatInputBarPresenterProtocol,
    keyboardHandlerDelegate: KeyboardUpdatesHandlerDelegate,
    collectionHandler: CollectionViewEventsHandling?,
    viewPresentationHandler: ViewPresentationEventsHandling?
)

private final class DefaultKeyboardHandler: KeyboardUpdatesHandlerDelegate {

    weak var presenter: BaseChatInputBarPresenterProtocol?

    init(presenter: BaseChatInputBarPresenterProtocol) {
        self.presenter = presenter
    }

    func didAdjustBottomMargin(to margin: CGFloat, state: KeyboardState) {
        guard let presenter = self.presenter?.viewController else { return }

        presenter.changeInputContentBottomMarginWithDefaultAnimation(
            to: margin,
            completion: nil
        )
    }
}
